local metricsCatalog = import 'servicemetrics/metrics-catalog.libsonnet';
local resourceSaturationPoint = (import 'servicemetrics/resource_saturation_point.libsonnet').resourceSaturationPoint;
local labelTaxonomy = import 'label-taxonomy/label-taxonomy.libsonnet';
local config = import './gitlab-metrics-config.libsonnet';

local rdsMonitoring = std.get(config.options, 'rdsMonitoring', false);
local rdsInstanceRAMBytes = std.get(config.options, 'rdsInstanceRAMBytes', null);

{
  [if rdsMonitoring && rdsInstanceRAMBytes != null then 'aws_rds_memory_saturation']: resourceSaturationPoint({
    title: 'Memory Availability for an RDS instance',
    severity: 's4',
    horizontallyScalable: false,
    appliesTo: ['rds'],
    description: |||
      The amount of available random access memory. This metric reports the value of the MemAvailable field of /proc/meminfo.

      A high saturation point indicates that we are low on available memory and Swap may be in use, lowering the performance of an RDS instance.

      Additional details here: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-metrics.html#rds-cw-metrics-instance
    |||,
    grafana_dashboard_uid: 'aws_rds_memory_saturation',
    resourceLabels: [],

    // Note we are doing an inverse of the supplied metric in order
    // to leverage saturation in a more universal way.  Example
    // high saturation, say 99% would mean there's less than a few
    // MB of available RAM that is freeable.
    query: |||
      1- (
        sum by (dbinstance_identifier) (aws_rds_freeable_memory_maximum)
        /
        %(rdsInstanceRAMBytes)s
      )
    ||| % {
      // Note that this value can be an integer bytes value, or a
      // PromQL expression, such as a recording rule
      rdsInstanceRAMBytes: rdsInstanceRAMBytes,
    },
    slos: {
      soft: 0.85,
      hard: 0.90,
      alertTriggerDuration: '30m',
    },
  }),
}
