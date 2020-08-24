local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local rateMetric = metricsCatalog.rateMetric;
local customApdex = metricsCatalog.customApdex;
local combined = metricsCatalog.combined;
local gitalyHelpers = import './lib/gitaly-helpers.libsonnet';
local toolingLinks = import 'toolinglinks/toolinglinks.libsonnet';

metricsCatalog.serviceDefinition({
  type: 'gitaly',
  tier: 'stor',
  // Since each Gitaly node is a SPOF for a subset of repositories, we need to ensure that
  // we have node-level monitoring on these hosts
  nodeLevelMonitoring: true,
  monitoringThresholds: {
    apdexScore: 0.999,
    errorRatio: 0.9995,
  },
  serviceDependencies: {
    gitaly: true,
  },
  components: {
    goserver: {
      local baseSelector = { job: 'gitaly' },
      apdex: gitalyHelpers.grpcServiceApdex(baseSelector),

      requestRate: rateMetric(
        counter='gitaly_service_client_requests_total',
        selector=baseSelector
      ),

      errorRate: combined([
        rateMetric(
          counter='gitaly_service_client_requests_total',
          selector=baseSelector {
            grpc_code: { nre: 'OK|NotFound|Unauthenticated|AlreadyExists|FailedPrecondition|DeadlineExceeded' },
          }
        ),
        rateMetric(
          counter='gitaly_service_client_requests_total',
          selector=baseSelector {
            grpc_code: 'DeadlineExceeded',
            deadline_type: { ne: 'limited' },
          }
        ),
      ]),

      significantLabels: ['fqdn'],

      toolingLinks: [
        toolingLinks.continuousProfiler(service='gitaly'),
        toolingLinks.sentry(slug='gitlab/gitaly-production'),
        toolingLinks.kibana(title='Gitaly', index='gitaly', stage='$stage', slowRequestSeconds=60),
      ],
    },

    gitalyruby: {
      local baseSelector = { job: 'gitaly' },

      // Uses the goservers histogram, but only selects client unary calls: this is an effective proxy
      // go gitaly-ruby client call times
      apdex: customApdex(
        rateQueryTemplate=|||
          rate(grpc_server_handling_seconds_bucket{%(selector)s}[%(rangeInterval)s]) and on(grpc_service,grpc_method) grpc_client_handled_total{job="gitaly"}
        |||,
        selector=baseSelector {
          grpc_type: 'unary',
          grpc_service: { ne: 'gitaly.OperationService' },
          grpc_method: { nre: gitalyHelpers.gitalyApdexIgnoredMethodsRegexp },
        },
        satisfiedThreshold=10,
        toleratedThreshold=30
      ),

      requestRate: rateMetric(
        counter='grpc_client_handled_total',
        selector=baseSelector
      ),

      errorRate: rateMetric(
        counter='grpc_client_handled_total',
        selector=baseSelector {
          grpc_code: { nre: 'OK|NotFound|Unauthenticated|AlreadyExists|FailedPrecondition|DeadlineExceeded' },
        }
      ),

      significantLabels: ['fqdn'],

      toolingLinks: [
        toolingLinks.sentry(slug='gitlab/gitlabcom-gitaly-ruby'),
      ],
    },
  },
})
