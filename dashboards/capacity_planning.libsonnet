local basic = import 'basic.libsonnet';
local colors = import 'colors.libsonnet';
local commonAnnotations = import 'common_annotations.libsonnet';
local grafana = import 'grafonnet/grafana.libsonnet';
local layout = import 'layout.libsonnet';
local platformLinks = import 'platform_links.libsonnet';
local promQuery = import 'prom_query.libsonnet';
local seriesOverrides = import 'series_overrides.libsonnet';
local templates = import 'templates.libsonnet';
local thresholds = import 'thresholds.libsonnet';
local dashboard = grafana.dashboard;
local row = grafana.row;
local graphPanel = grafana.graphPanel;
local row = grafana.row;
local tablePanel = grafana.tablePanel;

local findIssuesLink = 'https://gitlab.com/dashboard/issues?scope=all&utf8=✓&state=all&label_name[]=GitLab.com%20Resource%20Saturation&search=${__cell_1}+${__cell_3}';

local saturationTable(title, description, query, saturationDays, valueColumnName) =
  tablePanel.new(
    title,
    description=description,
    datasource='$PROMETHEUS_DS',
    styles=[{
      "alias": "Satuation Resource",
      "link": true,
      "linkTargetBlank": true,
      "linkTooltip": "Click the link to review the past " + saturationDays + " day(s) history for this saturation point.",
      "linkUrl": "https://dashboards.gitlab.net/d/alerts-saturation_component/alerts-saturation-component-alert?var-environment=gprd&var-type=${__cell_3}&var-stage=${__cell_2}&var-component=${__cell_1}&from=now-" + saturationDays + "d&to=now",
      "mappingType": 1,
      "pattern": "component",
      "type": "string"
    },
    {
      "alias": "Type",
      "mappingType": 1,
      "pattern": "type",
      "thresholds": [],
      "type": "string",
    },
    {
      "alias": valueColumnName,
      "colorMode": "row",
      "colors": [
        colors.errorColor,
        colors.errorColor,
        colors.errorColor,
      ],
      "mappingType": 1,
      "pattern": "Value",
      "thresholds": [
        "0",
        "100"
      ],
      "type": "number",
      "unit": "percentunit",
      decimals: 2,
    },
    {
      "alias": "Stage",
      "mappingType": 2,
      "pattern": "stage",
      "type": "string",
    },
    { // Sneaky repurposing of the Time column as a find issues link
      "alias": "Issues",
      "mappingType": 2,
      "pattern": "Time",
      "type": "string",
      "rangeMaps": [
        {
          "from": "0",
          "to": "9999999999999",
          "text": "Find Issues"
        }
      ],
      "link": true,
      "linkTargetBlank": true,
      "linkUrl": findIssuesLink,
      "linkTooltip": "Click the link to find issues on GitLab.com related to this saturation point."
    },
    {
      "alias": "",
      "mappingType": 1,
      "pattern": "/.*/",
      "type": "hidden"
    }],
  )
  .addTarget(promQuery.target(query, instant=true, format="table")) + {
    sort: {
      col: 13,
      desc: true
    },
  };

local currentSaturationBreaches(nodeSelector) =
    saturationTable('Current Saturation Point Breaches',
      description='Lists saturation points that are breaching their soft SLO thresholds at this instant',
      query='
      max by (type, stage, component) (
        clamp_max(
          gitlab_component_saturation:ratio{
            environment="$environment",
              ' + nodeSelector + '
          }
          ,
          1
        ) >= on(component, monitor, env) group_left slo:max:soft:gitlab_component_saturation:ratio
      )
    ',
    saturationDays=1, valueColumnName="Current %");

local currentSaturationWarnings(nodeSelector) =
    saturationTable('Current Saturation Point Warnings',
    description='Lists resource saturation metrics that, given their current value and weekly variance, have a high probability of breaching their soft thresholds limits',
    query='
      sort_desc(
        max by (type, stage, component) (
          clamp_max(
            gitlab_component_saturation:ratio:avg_over_time_1w{
              environment="$environment",
              ' + nodeSelector + '
            } +
            2 *
              gitlab_component_saturation:ratio:stddev_over_time_1w{
                environment="$environment",
              ' + nodeSelector + '
              }
            , 1
          )
          >= on(component, monitor, env) group_left slo:max:soft:gitlab_component_saturation:ratio
        )
      )
    ',
    saturationDays=7, valueColumnName="Likely Current Worst Case %");

local twoWeekSaturationWarnings(nodeSelector) =
    saturationTable('14d Future Predicted Saturation Point Warnings (using past 1w growth, linearly interpolated forward 14d)',
      description='Lists resource saturation metrics that, given their growth rate over the the past week, and their weekly variance, have a high probability of breaching their soft thresholds limits in the next 14d',
      query='
      sort_desc(
        max by (type, stage, component) (
          clamp_max(
            gitlab_component_saturation:ratio:predict_linear_2w{
              environment="$environment",
              ' + nodeSelector + '
            } +
            2 *
              gitlab_component_saturation:ratio:stddev_over_time_1w{
                environment="$environment",
              ' + nodeSelector + '
              }
          , 1
          )
          >= on(component, monitor, env) group_left slo:max:soft:gitlab_component_saturation:ratio
        )
      )
    ',
    saturationDays=30, valueColumnName="Predicted Worst Case % in 14d");

{
  environmentCapacityPlanningRow()::
    local nodeSelector = 'type!="", component!=""';
    row.new(title='📆 Capacity Planning', collapse=true)
      .addPanels(layout.grid([
        currentSaturationBreaches(nodeSelector),
        currentSaturationWarnings(nodeSelector),
        twoWeekSaturationWarnings(nodeSelector),
      ], cols=1)),

  capacityPlanningRow(serviceType, serviceStage)::
    local nodeSelector = 'type="' + serviceType + '", stage=~"|' + serviceStage + '"';
    row.new(title='📆 Capacity Planning', collapse=true)
    .addPanels(layout.grid([
      currentSaturationBreaches(nodeSelector),
      currentSaturationWarnings(nodeSelector),
      twoWeekSaturationWarnings(nodeSelector),
    graphPanel.new(
      'Long-term Resource Saturation',
      description='Resource saturation levels for saturation components for this service. Lower is better.',
      sort='decreasing',
      linewidth=1,
      fill=0,
      datasource='$PROMETHEUS_DS',
      decimals=0,
      legend_show=true,
      legend_hideEmpty=true,
    )
    .addTarget(
      promQuery.target(
        'clamp_min(clamp_max(
          max(
            gitlab_component_saturation:ratio{
              type="' + serviceType + '",
              environment="$environment",
              stage=~"|' + serviceStage + '"
            }
          ) by (component)
          ,1),0)
        ',
        legendFormat='{{ component }}',
        interval='5m',
        intervalFactor=5
      )
    )
    .resetYaxes()
    .addYaxis(
      format='percentunit',
      min=0,
      max=1,
      label='Saturation %',
    )
    .addYaxis(
      format='short',
      min=0,
      show=false,
    ) {
      timeFrom: '21d',
      seriesOverrides+: seriesOverrides.capacityThresholds + [seriesOverrides.capacityTrend],
    },
    graphPanel.new(
      'Long-term Resource Saturation - Rolling 1w average trend',
      description='Percentage of time that resource is within capacity SLOs. Higher is better.',
      sort='decreasing',
      linewidth=1,
      fill=0,
      datasource='$PROMETHEUS_DS',
      decimals=0,
      legend_show=true,
      legend_hideEmpty=true,
      thresholds=[
        thresholds.warningLevel('gt', 0.85),
        thresholds.errorLevel('lt', 0.95),
      ]
    )
    .addTarget(
      promQuery.target(
        'clamp_min(
          clamp_max(
            max(
              gitlab_component_saturation:ratio:avg_over_time_1w{
                type="' + serviceType + '",
                environment="$environment",
                stage=~"' + serviceStage + '|"
              }
            ) by (component)
          ,1),0)
        ',
        legendFormat='{{ component }}',
        interval='5m',
        intervalFactor=5
      )
    )
    .resetYaxes()
    .addYaxis(
      format='percentunit',
      max=1,
      label='Saturation %',
    )
    .addYaxis(
      format='short',
      max=1,
      min=0,
      show=false,
    ) {
      timeFrom: '21d',
      seriesOverrides+: seriesOverrides.capacityThresholds + [seriesOverrides.capacityTrend],
    },
  ], cols=1)),
}
