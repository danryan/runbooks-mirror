local metricsCatalog = import '../lib/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;
local customQuery = metricsCatalog.customQuery;

{
  type: 'registry',
  tier: 'sv',
  slos: {
    apdexRatio: 0.9,
    errorRatio: 0.005,
  },
  components: {
    // The registry only has a single component, the docker/distribution server
    server: {
      apdex: histogramApdex(
        histogram='registry_http_request_duration_seconds_bucket',
        selector='type="registry"',
        satisfiedThreshold=1,
        toleratedThreshold=2.5
      ),

      requestRate: rateMetric(
        counter='registry_http_requests_total',
        selector='type="registry"'
      ),

      errorRate: rateMetric(
        counter='registry_http_requests_total',
        selector='type="registry", code=~"5.."'
      ),
    },
  },
}
