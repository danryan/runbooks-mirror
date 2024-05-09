local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local toolingLinks = import 'toolinglinks/toolinglinks.libsonnet';

local rateMetric = metricsCatalog.rateMetric;
local histogramApdex = metricsCatalog.histogramApdex;

metricsCatalog.serviceDefinition({
  // This is important for recording-rules corresponding to this
  // service to be evaluated on Thanos instead. Within services
  // owned by Monitor::Observability, we ship our metrics to an
  // internal Thanos instance which is then setup as a remote
  // query endpoint for the upstream GitLab Thanos instance, see
  // https://thanos.gitlab.net/stores -> thanos-query.opstracegcp.com:80
  dangerouslyThanosEvaluated: true,

  tenants: [ 'gitlab-observability' ],

  type: 'errortracking',
  tier: 'sv',
  monitoringThresholds: {
    apdexScore: 0.995,
    errorRatio: 0.999,
  },
  serviceDependencies: {
    api: true,
  },
  provisioning: {
    kubernetes: false,
    vms: false,
  },
  serviceLevelIndicators: {
    loadbalancer: {
      severity: 's3',  // Don't page SREs for this SLI
      userImpacting: false,
      serviceAggregation: true,
      team: 'observability',
      featureCategory: 'error_tracking',
      description: |||
        Error Tracking allows developers to discover and view errors generated by their application
      |||,

      local errortrackingSelector = {
        team: 'observability',
        job: 'default/traefik',
        service: { re: '.*errortracking-api.*' },
      },

      requestRate: rateMetric(
        counter='traefik_service_requests_total',
        selector=errortrackingSelector,
      ),

      errorRate: rateMetric(
        counter='traefik_service_requests_total',
        selector=errortrackingSelector {
          code: { re: '^5.*' },
        },
      ),

      apdex: histogramApdex(
        histogram='traefik_service_request_duration_seconds_bucket',
        selector=errortrackingSelector { code: { noneOf: ['4xx', '5xx'] } },
        satisfiedThreshold='1.2',
        toleratedThreshold='5'
      ),

      emittedBy: [],  // TODO: Add type label in the source metrics https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/2873

      significantLabels: [],

      toolingLinks: [
        toolingLinks.kibana(title='Observability', index='observability'),
      ],
    },
  },
})
