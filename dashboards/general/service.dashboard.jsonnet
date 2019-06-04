local grafana = import 'grafonnet/grafana.libsonnet';
local seriesOverrides = import 'series_overrides.libsonnet';
local commonAnnotations = import 'common_annotations.libsonnet';
local promQuery = import 'prom_query.libsonnet';
local templates = import 'templates.libsonnet';
local colors = import 'colors.libsonnet';
local dashboard = grafana.dashboard;
local row = grafana.row;
local template = grafana.template;
local graphPanel = grafana.graphPanel;
local annotation = grafana.annotation;

local generalGraphPanel(
  title,
  description=null
) = graphPanel.new(
    title,
    linewidth=2,
    fill=0,
    datasource="$PROMETHEUS_DS",
    description=description,
    decimals=2,
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
  .addSeriesOverride(seriesOverrides.goldenMetric("/ service/"))
  .addSeriesOverride(seriesOverrides.upper)
  .addSeriesOverride(seriesOverrides.lower)
  .addSeriesOverride(seriesOverrides.upperLegacy)
  .addSeriesOverride(seriesOverrides.lowerLegacy)
  .addSeriesOverride(seriesOverrides.lastWeek)
  .addSeriesOverride(seriesOverrides.alertFiring)
  .addSeriesOverride(seriesOverrides.alertPending)
  .addSeriesOverride(seriesOverrides.slo);

local activeAlertsPanel() = grafana.tablePanel.new(
    'Active Alerts',
    datasource="$PROMETHEUS_DS",
    styles=[{
      "type": "hidden",
      "pattern": "Time",
      "alias": "Time",
    }, {
      "unit": "short",
      "type": "string",
      "alias": "Alert",
      "decimals": 2,
      "pattern": "alertname",
      "mappingType": 2,
      "link": true,
      "linkUrl": "https://alerts.${environment}.gitlab.net/#/alerts?filter=%7Balertname%3D%22${__cell}%22%2C%20env%3D%22${environment}%22%2C%20type%3D%22${type}%22%7D",
      "linkTooltip": "Open alertmanager",
    }, {
      "unit": "short",
      "type": "number",
      "alias": "Score",
      "decimals": 0,
      "colors": [
        colors.warningColor,
        colors.errorColor,
        colors.criticalColor
      ],
      "colorMode": "row",
      "pattern": "Value",
      "thresholds": [
        "2",
        "3"
      ],
      "mappingType": 1
    }
  ],
  )
  .addTarget( // Alert scoring
    promQuery.target('
      sort(
        max(
        ALERTS{environment="$environment", type="$type", stage="$stage", severity="critical", alertstate="firing"} * 3
        or
        ALERTS{environment="$environment", type="$type", stage="$stage", severity="error", alertstate="firing"} * 2
        or
        ALERTS{environment="$environment", type="$type", stage="$stage", severity="warn", alertstate="firing"}
        ) by (alertname, severity)
      )
      ',
      format="table",
      instant=true
    )
  );

local latencySLOPanel() = grafana.singlestat.new(
    '7d Latency SLO Error Budget',
    datasource="$PROMETHEUS_DS",
    format='percentunit',
  )
  .addTarget(
    promQuery.target('
        avg(avg_over_time(slo_observation_status{slo="error_ratio", environment="$environment", type="$type", stage="$stage"}[7d]))
      ',
      instant=true
    )
  );

local errorRateSLOPanel() = grafana.singlestat.new(
    '7d Apdex Rate SLO Error Budget',
    datasource="$PROMETHEUS_DS",
    format='percentunit',
  )
  .addTarget(
    promQuery.target('
        avg_over_time(slo_observation_status{slo="apdex_ratio",  environment="$environment", type="$type", stage="$stage"}[7d])
      ',
      instant=true
    )
  );


local apdexPanel() = generalGraphPanel(
    "Latency: Apdex",
    description="Apdex is a measure of requests that complete within a tolerable period of time for the service. Higher is better.",
  )
  .addTarget( // Primary metric
    promQuery.target('
      min(
        min_over_time(
          gitlab_service_apdex:ratio{environment="$environment", type="$type", stage="$stage"}[$__interval]
        )
      ) by (type)
      ',
      legendFormat='{{ type }} service',
    )
  )
 .addTarget( // Legacy metric - remove 2020-01-01
    promQuery.target('
      min(
        min_over_time(
          gitlab_service_apdex:ratio{environment="$environment", type="$type", stage=""}[$__interval]
        )
      ) by (type)
      ',
      legendFormat='{{ type }} service (legacy)',
    )
  )
  .addTarget( // Min apdex score SLO for gitlab_service_errors:ratio metric
    promQuery.target('
        avg(slo:min:gitlab_service_apdex:ratio{environment="$environment", type="$type", stage="$stage"}) or avg(slo:min:gitlab_service_apdex:ratio{type="$type"})
      ',
      interval="5m",
      legendFormat='SLO',
    ),
  )
  .addTarget( // Last week
    promQuery.target('
      min(
        min_over_time(
          gitlab_service_apdex:ratio{environment="$environment", type="$type", stage="$stage"}[$__interval] offset 1w
        )
      ) by (type)
      ',
      legendFormat='last week',
    )
  )
  .resetYaxes()
  .addYaxis(
    format='percentunit',
    max=1,
    label="Apdex %",
  )
  .addYaxis(
    format='short',
    max=1,
    min=0,
    show=false,
  );

local errorRatesPanel() =
  generalGraphPanel(
    "Error Ratios",
    description="Error rates are a measure of unhandled service exceptions within a minute period. Client errors are excluded when possible. Lower is better"
  )
  .addTarget( // Primary metric
    promQuery.target('
      max(
        max_over_time(
          gitlab_service_errors:ratio{environment="$environment", type="$type", stage="$stage"}[$__interval]
        )
      ) by (type)
      ',
      legendFormat='{{ type }} service',
    )
  )
  .addTarget( // Legacy metric - remove 2020-01-01
    promQuery.target('
      max(
        max_over_time(
          gitlab_service_errors:ratio{environment="$environment", type="$type", stage=""}[$__interval]
        )
      ) by (type)
      ',
      legendFormat='{{ type }} service (legacy)',
    )
  )
  .addTarget( // Maximum error rate SLO for gitlab_service_errors:ratio metric
    promQuery.target('
        avg(slo:max:gitlab_service_errors:ratio{environment="$environment", type="$type", stage="$stage"}) or avg(slo:max:gitlab_service_errors:ratio{type="$type"})
      ',
      interval="5m",
      legendFormat='SLO',
    ),
  )
  .addTarget( // Last week
    promQuery.target('
      max(
        max_over_time(
          gitlab_service_errors:ratio{environment="$environment", type="$type", stage="$stage"}[$__interval] offset 1w
        )
      ) by (type)
      ',
      legendFormat='last week',
    )
  )
  .resetYaxes()
  .addYaxis(
    format='percentunit',
    min=0,
    label="% Requests in Error",
  )
  .addYaxis(
    format='short',
    max=1,
    min=0,
    show=false,
  );

local serviceAvailabilityPanel() =
  generalGraphPanel(
    "Service Availability",
    description="Availability measures the ratio of component processes in the service that are currently healthy and able to handle requests. The closer to 100% the better."
  )
  .addTarget( // Primary metric
    promQuery.target('
      min(
        min_over_time(
          gitlab_service_availability:ratio{environment="$environment", type="$type", stage="$stage"}[$__interval]
        )
      ) by (tier, type)
      ',
      legendFormat='{{ type }} service',
    )
  )
  .addTarget( // Legacy metric
    promQuery.target('
      min(
        min_over_time(
          gitlab_service_availability:ratio{environment="$environment", type="$type", stage=""}[$__interval]
        )
      ) by (tier, type)
      ',
      legendFormat='{{ type }} service (legacy)',
    )
  )
  .addTarget( // Last week
    promQuery.target('
      min(
        min_over_time(
          gitlab_service_availability:ratio{environment="$environment", type="$type", stage="$stage"}[$__interval] offset 1w
        )
      ) by (tier, type)
      ',
      legendFormat='last week',
    )
  )
  .resetYaxes()
  .addYaxis(
    format='percentunit',
    max=1,
    label="Availability %",
  )
  .addYaxis(
    format='short',
    max=1,
    min=0,
    show=false,
  );

local qpsPanel() =
  generalGraphPanel(
    "RPS - Service Requests per Second",
    description="The operation rate is the sum total of all requests being handle for all components within this service. Note that a single user request can lead to requests to multiple components. Higher is busier."
  )
  .addTarget( // Primary metric
    promQuery.target('
      max(
        avg_over_time(
          gitlab_service_ops:rate{environment="$environment", type="$type", stage="$stage"}[$__interval]
        )
      ) by (type)
      ',
      legendFormat='{{ type }} service',
    )
  )
  .addTarget( // Legacy metric - remove 2020-01-01
    promQuery.target('
      max(
        avg_over_time(
          gitlab_service_ops:rate{environment="$environment", type="$type", stage=""}[$__interval]
        )
      ) by (type)
      ',
      legendFormat='{{ type }} service (legacy)',
    )
  )
  .addTarget( // Last week
    promQuery.target('
      max(
        avg_over_time(
          gitlab_service_ops:rate{environment="$environment", type="$type", stage="$stage"}[$__interval] offset 1w
        )
      ) by (type)
      ',
      legendFormat='last week',
    )
  )
  .addTarget(
    promQuery.target('
      gitlab_service_ops:rate:prediction{environment="$environment", type="$type", stage="$stage"} +
      $sigma * gitlab_service_ops:rate:stddev_over_time_1w{environment="$environment", type="$type", stage="$stage"}
      ',
      legendFormat='upper normal',
    ),
  )
  .addTarget(
    promQuery.target('
      avg(
        clamp_min(
          gitlab_service_ops:rate:prediction{environment="$environment", type="$type", stage="$stage"} -
          $sigma * gitlab_service_ops:rate:stddev_over_time_1w{environment="$environment", type="$type", stage="$stage"},
          0
        )
      )
      ',
      legendFormat='lower normal',
    ),
  )
  .addTarget( // Legacy metric - remove 2020-01-01
    promQuery.target('
      gitlab_service_ops:rate:prediction{environment="$environment", type="$type", stage=""} +
      $sigma * gitlab_service_ops:rate:stddev_over_time_1w{environment="$environment", type="$type", stage=""}
      ',
      legendFormat='upper normal (legacy)',
    ),
  )
  .addTarget( // Legacy metric - remove 2020-01-01
    promQuery.target('
      avg(
        clamp_min(
          gitlab_service_ops:rate:prediction{environment="$environment", type="$type", stage=""} -
          $sigma * gitlab_service_ops:rate:stddev_over_time_1w{environment="$environment", type="$type", stage=""},
          0
        )
      )
      ',
      legendFormat='lower normal (legacy)',
    ),
  )
  .resetYaxes()
  .addYaxis(
    format='short',
    min=0,
    label="Operations per Second",
  )
  .addYaxis(
    format='short',
    max=1,
    min=0,
    show=false,
  );


dashboard.new(
  'Service Platform Metrics',
  schemaVersion=16,
  tags=['general'],
  timezone='UTC',
  graphTooltip='shared_crosshair',
)
.addAnnotation(commonAnnotations.deploymentsForEnvironment)
.addAnnotation(commonAnnotations.deploymentsForEnvironmentCanary)
.addTemplate(templates.ds)
.addTemplate(templates.environment)
.addTemplate(templates.type)
.addTemplate(templates.stage)
.addTemplate(templates.sigma)
.addPanel(latencySLOPanel(),
  gridPos={
    x: 0,
    y: 0,
    w: 6,
    h: 4,
})
.addPanel(activeAlertsPanel(),
  gridPos={
    x: 6,
    y: 0,
    w: 18,
    h: 8,
})
.addPanel(errorRateSLOPanel(),
  gridPos={
    x: 0,
    y: 4,
    w: 6,
    h: 4,
})
.addPanel(
  apdexPanel(),
  gridPos={
    x: 0,
    y: 10,
    w: 12,
    h: 10,
  }
)
.addPanel(
  errorRatesPanel(),
  gridPos={
    x: 12,
    y: 10,
    w: 12,
    h: 10,
  }
)
.addPanel(
  serviceAvailabilityPanel(),
  gridPos={
    x: 0,
    y: 20,
    w: 12,
    h: 10,
  }
)
.addPanel(
  qpsPanel(),
  gridPos={
    x: 12,
    y: 20,
    w: 12,
    h: 10,
  }
)
