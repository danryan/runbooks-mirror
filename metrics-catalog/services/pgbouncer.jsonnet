local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;
local combined = metricsCatalog.combined;
local toolingLinks = import 'toolinglinks/toolinglinks.libsonnet';

metricsCatalog.serviceDefinition({
  type: 'pgbouncer',
  tier: 'db',
  serviceDependencies: {
    patroni: true,
  },
  components: {
    service: {
      // The same query, with different labels is also used on the patroni nodes pgbouncer instances
      requestRate: combined([
        rateMetric(
          counter='pgbouncer_stats_sql_transactions_pooled_total',
          selector='type="pgbouncer", tier="db"'
        ),
        rateMetric(
          counter='pgbouncer_stats_queries_pooled_total',
          selector='type="pgbouncer", tier="db"'
        ),
      ]),

      significantLabels: ['fqdn'],

      toolingLinks: [
        toolingLinks.kibana(title='pgbouncer', index='postgres_pgbouncer', type='pgbouncer', tag='postgres.pgbouncer'),
      ],
    },
  },
})
