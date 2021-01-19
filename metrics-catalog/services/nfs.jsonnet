local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;

metricsCatalog.serviceDefinition({
  type: 'nfs',
  tier: 'stor',
  monitoringThresholds: {
    errorRatio: 0.9999,  // 99.99% of nfs requests should succeed, over multiple window periods
  },
  serviceLevelIndicators: {
    nfs_service: {
      userImpacting: true,
      featureCategory: 'not_owned',
      team: 'sre_coreinfra',
      description: |||
        Monitors NFS RPC calls in aggregate.
      |||,

      requestRate: rateMetric(
        counter='node_nfsd_server_rpcs_total',
        selector='type="nfs"'
      ),

      errorRate: rateMetric(
        counter='node_nfsd_rpc_errors_total',
        selector='type="nfs"'
      ),

      significantLabels: ['fqdn'],
    },
  },
})
