local metricsCatalog = import 'servicemetrics/metrics-catalog.libsonnet';
local resourceSaturationPoint = (import 'servicemetrics/resource_saturation_point.libsonnet').resourceSaturationPoint;

{
  cloudsql_memory: resourceSaturationPoint({
    title: 'CloudSQL Memory Utilization',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: metricsCatalog.findServicesWithTag(tag='cloud-sql'),
    description: |||
      CloudSQL Memory utilization.

      See https://cloud.google.com/monitoring/api/metrics_gcp#gcp-cloudsql for
      more details
    |||,
    grafana_dashboard_uid: 'sat_cloudsql_memory',
    resourceLabels: ['database_id'],
    burnRatePeriod: '5m',
    staticLabels: {
      type: 'monitoring',
      tier: 'inf',
      stage: 'main',
    },
    query: |||
      avg_over_time(stackdriver_cloudsql_database_cloudsql_googleapis_com_database_memory_utilization{%(selector)s}[%(rangeInterval)s])
    |||,
    slos: {
      capacity_planning: 0.80,
      hard: 0.90,
    },
  }),
}
