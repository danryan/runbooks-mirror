local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local resourceSaturationPoint = metricsCatalog.resourceSaturationPoint;

{
  pgbouncer_client_conn: resourceSaturationPoint({
    title: 'PGBouncer Client Connections per Process',
    severity: 's2',
    horizontallyScalable: true,  // Add more pgbouncer processes
    appliesTo: ['patroni', 'pgbouncer'],
    description: |||
      Client connections per pgbouncer process.

      pgbouncer is configured to use a `max_client_conn` setting. This limits the total number of client connections per pgbouncer.

      When this limit is reached, client connections may be refused, and `max_client_conn` errors may appear in the pgbouncer logs.

      This could affect users as Rails clients are left unable to connect to the database. Another potential knock-on effect
      is that Rails clients could fail their readiness checks for extended periods during a deployment, leading to saturation of
      the older nodes.
    |||,
    grafana_dashboard_uid: 'sat_pgbouncer_client_conn',
    resourceLabels: ['fqdn'],
    burnRatePeriod: '5m',
    queryFormatConfig: {
      /** This value is configured in chef - make sure that it's kept in sync */
      maxClientConns: 6200,
    },
    query: |||
      avg_over_time(pgbouncer_pools_client_active_connections {%(selector)s}[%(rangeInterval)s])
      /
      %(maxClientConns)g
    |||,
    slos: {
      soft: 0.90,
      hard: 0.95,
    },
  }),
}
