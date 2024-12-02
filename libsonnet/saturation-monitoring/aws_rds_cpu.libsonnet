local metricsCatalog = import 'servicemetrics/metrics-catalog.libsonnet';
local resourceSaturationPoint = (import 'servicemetrics/resource_saturation_point.libsonnet').resourceSaturationPoint;
local labelTaxonomy = import 'label-taxonomy/label-taxonomy.libsonnet';
local config = import './gitlab-metrics-config.libsonnet';

local rdsMonitoring = std.get(config.options, 'rdsMonitoring', false);

{
  [if rdsMonitoring then 'aws_rds_cpu_utilization']: resourceSaturationPoint({
    title: 'CPU Utilization per RDS Instance',
    severity: 's2',
    horizontallyScalable: false,
    appliesTo: ['rds'],
    description: |||
      The percentage of CPU utilization.

      Additional details here: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-metrics.html#rds-cw-metrics-instance
    |||,
    grafana_dashboard_uid: 'aws_rds_cpu_utilization',
    resourceLabels: [],

    // This value is presented as a percentage.  We divide by 100 such that it is more consistent with our metrics system.
    query: 'aws_rds_cpuutilization_maximum / 100',
    slos: {
      soft: 0.90,
      hard: 0.95,
      alertTriggerDuration: '15m',
    },
  }),
}
