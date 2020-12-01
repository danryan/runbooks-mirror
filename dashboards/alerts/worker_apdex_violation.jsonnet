local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local basic = import 'grafana/basic.libsonnet';
local commonAnnotations = import 'grafana/common_annotations.libsonnet';
local layout = import 'grafana/layout.libsonnet';
local promQuery = import 'grafana/prom_query.libsonnet';
local seriesOverrides = import 'grafana/series_overrides.libsonnet';
local templates = import 'grafana/templates.libsonnet';
local platformLinks = import 'platform_links.libsonnet';
local dashboard = grafana.dashboard;
local row = grafana.row;
local template = grafana.template;
local graphPanel = grafana.graphPanel;
local annotation = grafana.annotation;
local seriesOverrides = import 'grafana/series_overrides.libsonnet';

local sidekiqQueueLatency() =
  basic.latencyTimeseries(
    title='Queue Latency',
    description='${percentile}th percentile queue latency. Lower is better.',
    query=|||
      histogram_quantile($percentile/100, sum(rate(sidekiq_jobs_completion_seconds_bucket{environment="$environment", queue="$queue"}[$__interval])) by (le, environment, stage, tier, type, queue))
    |||,
    legendFormat='{{ queue }}'
  )
  .addTarget(
    promQuery.target('$threshold', legendFormat='threshold')
  )
  .addSeriesOverride(seriesOverrides.thresholdSeries('threshold'));

basic.dashboard(
  'Worker Apdex Violation Alert',
  tags=['alert-target', 'sidekiq'],
)
.addTemplate(templates.sidekiqQueue)
.addTemplate(
  template.custom(
    'threshold',
    '0.025,0.05,0.1,0.25,0.5,1,2.5,5,10,25,50',
    '1',
  )
)
.addTemplate(
  template.custom(
    'percentile',
    '50,80,90,95,99',
    '95',
  )
)
.addPanels(layout.grid([
  sidekiqQueueLatency(),
], cols=1, rowHeight=10))
+ {
  links+: platformLinks.serviceLink('sidekiq') + platformLinks.triage,
}
