local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;

metricsCatalog.serviceDefinition({
  type: 'jaeger',
  tier: 'inf',
  monitoringThresholds: {
    // apdexScore: 0.999,
    errorRatio: 0.999,
  },
  serviceLevelIndicators: {
    jaeger_agent: {
      userImpacting: false,
      requestRate: rateMetric(
        counter='jaeger_agent_reporter_spans_submitted_total',
      ),

      errorRate: rateMetric(
        counter='jaeger_agent_reporter_spans_failures_total',
      ),

      significantLabels: ['fqdn', 'instance'],
    },

    jaeger_collector: {
      userImpacting: false,
      apdex: histogramApdex(
        histogram='jaeger_collector_save_latency_bucket',
        satisfiedThreshold=10,
      ),

      requestRate: rateMetric(
        counter='jaeger_collector_spans_received_total',
      ),

      errorRate: rateMetric(
        counter='jaeger_collector_spans_dropped_total',
      ),

      significantLabels: ['fqdn', 'pod'],
    },

    jaeger_query: {
      userImpacting: false,
      apdex: histogramApdex(
        histogram='jaeger_query_latency_bucket',
        satisfiedThreshold=10,
      ),

      requestRate: rateMetric(
        counter='jaeger_query_requests_total',
      ),

      errorRate: rateMetric(
        counter='jaeger_query_requests_total',
        selector={ result: { re: 'err' } },
      ),

      significantLabels: ['fqdn', 'pod'],
    },
  },
  skippedMaturityCriteria: {
    'Service exists in the dependency graph': 'Jaeger is an independent internal observability tool',
    'Structured logs available in Kibana': 'Jaeger service is not deployed in production',
  },
})
