local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local rateMetric = metricsCatalog.rateMetric;

metricsCatalog.serviceDefinition({
  type: 'zoekt',
  tier: 'inf',
  monitoringThresholds: {
    apdexScore: 0.999,
    errorRatio: 0.999,
  },
  serviceLevelIndicators: {},
})
