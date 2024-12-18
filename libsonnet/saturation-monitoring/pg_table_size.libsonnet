local resourceSaturationPoint = (import 'servicemetrics/metrics.libsonnet').resourceSaturationPoint;
local metricsCatalog = import 'servicemetrics/metrics-catalog.libsonnet';

{
  pg_table_size: resourceSaturationPoint({
    title: 'Postgres Table Size',
    severity: 's4',
    horizontallyScalable: false,
    appliesTo: metricsCatalog.findServicesWithTag(tag='gitlab_monitor_bloat'),
    description: |||
      This measures the table size for each Postgres Table.
    |||,
    grafana_dashboard_uid: 'sat_pg_table_bloat',
    resourceLabels: ['fqdn'],
    burnRatePeriod: '5m',
    query: |||
      max by (relname, type, fqdn) (pg_total_relation_size_bytes{%(selectors)s})
    |||,
    slos: {
      soft: 0.40,
      hard: 0.50,
    },
  }),
}
