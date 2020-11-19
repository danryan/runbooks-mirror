local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;
local combined = metricsCatalog.combined;

metricsCatalog.serviceDefinition({
  type: 'pages',
  tier: 'lb',
  monitoringThresholds: {
    errorRatio: 0.9999,
  },
  /*
   * No need to have operation rate alerting for both pages and web-pages
   * so disabling it for this service, and keeping the anomaly detection
   * at the web-pages level
   */
  disableOpsRatePrediction: true,
  serviceLevelIndicators: {
    loadbalancer: {
      staticLabels: {
        stage: 'main',
      },

      requestRate: rateMetric(
        counter='haproxy_server_sessions_total',
        selector='type="pages", backend=~"pages_https|pages_http"'
      ),

      errorRate: combined([
        rateMetric(
          counter='haproxy_backend_http_responses_total',
          selector='type="pages",job="haproxy",code="5xx"'
        ),
        rateMetric(
          counter='haproxy_server_connection_errors_total',
          selector='type="pages", job="haproxy"'
        ),
      ]),

      significantLabels: [],
    },
  },
})
