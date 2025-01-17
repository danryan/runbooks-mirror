local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local platformLinks = import 'gitlab-dashboards/platform_links.libsonnet';
local metricsConfig = import 'gitlab-metrics-config.libsonnet';
local grafanaCalHeatmap = import 'grafana-cal-heatmap-panel/panel.libsonnet';
local basic = import 'grafana/basic.libsonnet';
local layout = import 'grafana/layout.libsonnet';
local row = grafana.row;
local selectors = import 'promql/selectors.libsonnet';
local seriesOverrides = import 'grafana/series_overrides.libsonnet';
local templates = import 'grafana/templates.libsonnet';
local thresholds = import 'gitlab-dashboards/thresholds.libsonnet';
local generalServicesDashboard = import 'general-services-dashboard.libsonnet';
local template = grafana.template;
local strings = import 'utils/strings.libsonnet';

local overviewDashboardLinks(type) =
  local formatConfig = { type: type };
  [
    {
      url: '/d/%(type)s-main/%(type)s-overview?orgId=1&${__url_time_range}' % formatConfig,
      title: '%(type)s service: Overview Dashboard' % formatConfig,
    },
  ];

local thresholdsValues = {
  thresholds: [
    thresholds.errorLevel('lt', metricsConfig.slaTarget),
  ],
};

// This graph shows a dynamic range: from the begining of last month to
// yesterday. This means that error budget in minutes also changed
// depending on $__range_ms. Since we cannot perform calculations in the
// threshold specification of a stat-panel we don't know the the budget
// in minutes to deduct thresholds.
//
// To avoid confusion, we'll show a single color as the background here.
// https://github.com/grafana/grafana/issues/922
local budgetMinutesColor = {
  color: 'light-blue',
  value: null,
};
local defaultSelector = {
  env: { re: 'ops|$environment' },
  environment: '$environment',
  stage: 'main',
  monitor: { re: 'global|' },
};

local systemAvailabilityQuery(selectorHash, rangeInterval) =
  |||
    avg_over_time(sla:gitlab:ratio{%(selectors)s}[%(rangeInterval)s])
  ||| % {
    selectors: selectors.serializeHash(defaultSelector + selectorHash),
    rangeInterval: rangeInterval,
  };

local templateServiceName(service) =
  '%s_weight' % [std.strReplace(service, '-', '_')];

local serviceWeights = {
  [service.name]: service.business.SLA.overall_sla_weighting
  for service in generalServicesDashboard.keyServices(includeZeroScore=true)
};

local weightableQuery(aggregation, service, rangeInterval) =
  local serviceWeightTemplate = '$%s' % [templateServiceName(service)];
  // TODO: `slo_observation_status` only exists in Thanos
  // whereas `slo:observation_status` only exists in Mimir. The or expression allows
  // us to show the graph from both data sources. Remove the slo_observation_status expression
  // once we have migrated to Mimir.
  |||
    %(aggregation)s without (slo) (
      avg_over_time(slo_observation_status{%(selector)s}[%(rangeInterval)s])
      or
      avg_over_time(slo:observation_status{%(selector)s}[%(rangeInterval)s])
    ) * %(weight)s
  ||| % {
    aggregation: aggregation,
    selector: selectors.serializeHash(defaultSelector { type: service }),
    weight: serviceWeightTemplate,
    rangeInterval: rangeInterval,
  };

local adjustableWeightQuery(rangeInterval) =
  local serviceScoreQueries = std.map(
    function(service)
      weightableQuery('min', service, rangeInterval),
    std.objectFields(serviceWeights)
  );
  local serviceWeightQueries = std.map(
    function(service)
      weightableQuery('group', service, rangeInterval),
    std.objectFields(serviceWeights)
  );
  |||
    sum by (environment, env, stage) (
      %(score)s
    )
    /
    sum by (environment, env, stage) (
      %(weight)s
    )
  ||| % {
    score: strings.chomp(strings.indent(std.join('\nor\n', serviceScoreQueries), 2)),
    weight: strings.chomp(strings.indent(std.join('\nor\n', serviceWeightQueries), 2)),
  };

// NB: this query takes into account values recorded in Prometheus prior to
// https://gitlab.com/gitlab-com/gl-infra/reliability/-/issues/9689
// Better fix proposed in https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/326
// This is encoded in the `defaultSelector`
local serviceAvailabilityQuery(selectorHash, metricName, fallbackMetricName, rangeInterval) =
  local defaultSelector = {
    env: { re: 'ops|$environment' },
    environment: '$environment',
    stage: 'main',
    monitor: { re: 'global|' },
  };

  // TODO: fallbackMetricName is used because `slo_observation_status` only exists in Thanos
  // whereas `slo:observation_status` only exists in Mimir. The fallbackMetricName allows us
  // to show the dashboard in both Thanos and Mimir. Remove the fallbackMetricName once
  // we have migrated to Mimir.
  |||
    min(
      clamp_max(
        avg_over_time(
          %(metricName)s{%(selector)s}[%(rangeInterval)s]
        )
        or
        avg_over_time(
          %(fallbackMetricName)s{%(selector)s}[%(rangeInterval)s]
        ),
        1
      )
    )
  ||| % {
    selector: selectors.serializeHash(defaultSelector + selectorHash),
    metricName: metricName,
    fallbackMetricName: fallbackMetricName,
    rangeInterval: rangeInterval,
  };

// NB: this query takes into account values recorded in Prometheus prior to
// https://gitlab.com/gitlab-com/gl-infra/reliability/-/issues/9689
// Better fix proposed in https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/326
// This is encoded in the `defaultSelector`
local serviceAvailabilityMillisecondsQuery(selectorHash, metricName, fallbackMetricName=null) =
  local defaultSelector = {
    env: { re: 'ops|$environment' },
    environment: '$environment',
    stage: 'main',
    monitor: { re: 'global|' },
  };

  // TODO: fallbackMetricName is used because `slo_observation_status` only exists in Thanos
  // whereas `slo:observation_status` only exists in Mimir. The fallbackMetricName allows us
  // to show the dashboard in both Thanos and Mimir. Remove the fallbackMetricName once
  // we have migrated to Mimir.
  |||
    (
      1 -
      min(
        clamp_max(
          avg_over_time(
            %(metricName)s{%(selector)s}[$__range]
          )
          %(backupExpression)s
          ,
          1
        )
      )
    ) * $__range_ms
  ||| % {
    selector: selectors.serializeHash(defaultSelector + selectorHash),
    metricName: metricName,
    backupExpression: if fallbackMetricName != null then |||
      or
      avg_over_time(%(fallbackMetricName)s{%(selector)s}[$__range])
    ||| % {
      fallbackMetricName: fallbackMetricName,
      selector: selectors.serializeHash(defaultSelector + selectorHash),
    } else '',
  };

local serviceRow(service) =
  local links = overviewDashboardLinks(service.name);
  [
    basic.slaStats(
      title='',
      query=serviceAvailabilityQuery({ type: service.name }, 'slo_observation_status', 'slo:observation_status', '$__range'),
      legendFormat='{{ type }}',
      displayName=service.friendly_name,
      links=links,
      intervalFactor=1,
    ),
    basic.slaStats(
      title='',
      query=serviceAvailabilityMillisecondsQuery({ type: service.name }, 'slo_observation_status', 'slo:observation_status'),
      legendFormat='{{ type }}',
      displayName='Budget Spent',
      links=links,
      decimals=1,
      unit='ms',
      colors=[budgetMinutesColor],
      colorMode='value',
      intervalFactor=1,
    ),
    basic.slaTimeseries(
      title='%s: SLA Trends ' % [service.friendly_name],
      description='Rolling average SLO adherence for primary services. Higher is better.',
      yAxisLabel='SLA',
      query=serviceAvailabilityQuery({ type: service.name }, 'slo_observation_status', 'slo:observation_status', '$__interval'),
      legendFormat='{{ type }}',
      intervalFactor=1,
      legend_show=false
    )
    .addDataLink(links) + thresholdsValues +
    {
      options: { dataLinks: links },
    },
  ];

local primaryServiceRows = std.map(serviceRow, generalServicesDashboard.sortedKeyServices());
local serviceWeightTemplates = [
  template.custom(
    name=templateServiceName(service),
    query='0,1,5',
    current='%s' % [serviceWeights[service]]
  )
  for service in std.map(function(s) s.name, generalServicesDashboard.sortedKeyServices())
];

basic.dashboard(
  'SLAs',
  tags=['general', 'slas', 'service-levels'],
  includeStandardEnvironmentAnnotations=false,
  time_from='now-1M/M',
  time_to='now-1d/d',
)
.addTemplate(
  templates.slaType,
).addTemplates(serviceWeightTemplates)
.addPanel(
  row.new(title='Overall System Availability'),
  gridPos={
    x: 0,
    y: 0,
    w: 24,
    h: 1,
  }
)
.addPanels(
  local systemSelector = { sla_type: '$sla_type' };
  layout.splitColumnGrid([
    [
      basic.slaStats(
        title='GitLab.com Availability',
        description='Recorded availability',
        query=systemAvailabilityQuery(systemSelector, '$__range'),
        intervalFactor=1,
      ),
      basic.slaStats(
        title='Gitlab.com Availability with selected weights',
        description='Availability taking into account weights from the dropdowns',
        query=adjustableWeightQuery('$__range'),
        intervalFactor=1,
      ),
    ],
    [basic.slaStats(
      title='',
      query=serviceAvailabilityMillisecondsQuery(systemSelector, 'sla:gitlab:ratio'),
      legendFormat='',
      displayName='Budget Spent',
      decimals=1,
      unit='ms',
      colors=[budgetMinutesColor],
      colorMode='value',
      intervalFactor=1,
    )],
    [basic.slaTimeseries(
       title='Overall SLA over time period - gitlab.com',
       description='Rolling average SLO adherence across all primary services. Higher is better.',
       yAxisLabel='SLA',
       query=systemAvailabilityQuery(systemSelector, '$__interval'),
       legendFormat='gitlab.com SLA',
       intervalFactor=1,
       legend_show=false
     )
     .addSeriesOverride(seriesOverrides.goldenMetric('gitlab.com SLA'))
     + thresholdsValues],
  ], cellHeights=[3, 2], columnWidths=[4, 4, 16], startRow=1)
)
.addPanel(
  row.new(title='Primary Services'),
  gridPos={
    x: 0,
    y: 2000,
    w: 24,
    h: 1,
  }
)
.addPanels(
  layout.columnGrid(primaryServiceRows, [4, 4, 16], rowHeight=5, startRow=2101)
)
.addPanels(
  layout.grid([
    grafana.text.new(
      title='GitLab SLA Dashboard Explainer',
      mode='markdown',
      content=|||
        This dashboard shows the SLA trends for each of the _primary_ services in the GitLab fleet ("primary" services are those which are directly user-facing).

        Read more details on our [SLA policy is defined in the handbook](https://about.gitlab.com/handbook/engineering/monitoring/).

        * For each service we measure two key metrics/SLIs (Service Level Indicators): error-rate and apdex score
        * For each service, for each SLI, we have an SLO target
          * For error-rate, the SLI should remain _below_ the SLO
          * For apdex score, the SLI should remain _above_ the SLO
        * The SLA for each service is the percentage of time that the _both_ SLOs are being met
        * The SLA for GitLab.com is the average SLO across each primary service

        _To see instanteous SLI values for these services, visit the [`general-public-splashscreen`](d/general-public-splashscreen) dashboard._
      |||
    ),
  ], cols=1, rowHeight=10, startRow=3001)
)
.trailer()
+ {
  links+: platformLinks.services + platformLinks.triage,
}
