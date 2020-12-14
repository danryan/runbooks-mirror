local capacityPlanning = import 'capacity_planning.libsonnet';
local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local layout = import 'grafana/layout.libsonnet';
local seriesOverrides = import 'grafana/series_overrides.libsonnet';
local templates = import 'grafana/templates.libsonnet';
local keyMetrics = import 'key_metrics.libsonnet';
local nodeMetrics = import 'node_metrics.libsonnet';
local platformLinks = import 'platform_links.libsonnet';
local serviceHealth = import 'service_health.libsonnet';
local dashboard = grafana.dashboard;
local row = grafana.row;
local template = grafana.template;
local graphPanel = grafana.graphPanel;
local annotation = grafana.annotation;
local basic = import 'grafana/basic.libsonnet';
local statusDescription = import 'status_description.libsonnet';

local selector = { environment: '$environment', stage: '$stage', type: '$type' };

local generalGraphPanel(title, description=null, linewidth=2, sort='increasing') =
  graphPanel.new(
    title,
    linewidth=linewidth,
    fill=0,
    datasource='$PROMETHEUS_DS',
    description=description,
    decimals=2,
    sort=sort,
    legend_show=true,
    legend_values=true,
    legend_min=true,
    legend_max=true,
    legend_current=true,
    legend_total=false,
    legend_avg=true,
    legend_alignAsTable=true,
    legend_hideEmpty=true,
  )
  .addSeriesOverride(seriesOverrides.goldenMetric('/ service/'))
  .addSeriesOverride(seriesOverrides.upper)
  .addSeriesOverride(seriesOverrides.lower)
  .addSeriesOverride(seriesOverrides.upperLegacy)
  .addSeriesOverride(seriesOverrides.lowerLegacy)
  .addSeriesOverride(seriesOverrides.lastWeek)
  .addSeriesOverride(seriesOverrides.alertFiring)
  .addSeriesOverride(seriesOverrides.alertPending)
  .addSeriesOverride(seriesOverrides.degradationSlo)
  .addSeriesOverride(seriesOverrides.outageSlo)
  .addSeriesOverride(seriesOverrides.slo);

basic.dashboard(
  'Service Platform Metrics',
  tags=['general'],
)
.addTemplate(templates.type)
.addTemplate(templates.stage)
.addTemplate(templates.sigma)
.addPanels(
  layout.grid([
    statusDescription.serviceApdexStatusDescriptionPanel(selector),
    statusDescription.serviceErrorStatusDescriptionPanel(selector),
  ], startRow=0, rowHeight=4)
)
.addPanel(
  row.new(title='🏅 Key Service Metrics'),
  gridPos={
    x: 0,
    y: 2000,
    w: 24,
    h: 1,
  }
)
.addPanels(
  layout.grid([
    keyMetrics.serviceApdexPanel('$type', '$stage'),
    keyMetrics.serviceErrorRatePanel('$type', '$stage'),
    keyMetrics.serviceOperationRatePanel('$type', '$stage'),
    keyMetrics.utilizationRatesPanel('$type', '$stage'),
  ], startRow=3001)
)
.addPanel(
  nodeMetrics.nodeMetricsDetailRow('environment="$environment", stage=~"|$stage", type="$type"'),
  gridPos={
    x: 0,
    y: 5000,
    w: 24,
    h: 1,
  }
)
.addPanel(capacityPlanning.capacityPlanningRow('$type', '$stage'), gridPos={ x: 0, y: 6000 })

+ {
  links+: platformLinks.services + platformLinks.triage,
}
