local utilizationMetric = (import 'servicemetrics/utilization_metric.libsonnet').utilizationMetric;
local metricsCatalog = import 'servicemetrics/metrics-catalog.libsonnet';

{
  pg_table_size: utilizationMetric({
    title: 'Total size of relations in PostgreSQL databases',
    unit: 'bytes',
    appliesTo: metricsCatalog.findServicesWithTag(tag='postgres'),
    description: |||
      Monitors the total on-disk size, including index and TOAST size, of PostgreSQL tables
    |||,
    resourceLabels: ['schemaname', 'relname'],
    query: |||
      avg by (%(aggregationLabels)s, schemaname, relname) (
        avg_over_time(pg_total_relation_size_bytes{%(selector)s}[%(rangeDuration)s])
        and on (job, instance) (
          pg_replication_is_replica{%(selector)s} == 0
        )
      )
    |||,
  }),
}
