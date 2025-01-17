local registryCustomRouteSLIs = import './lib/registry-custom-route-slis.libsonnet';
local sliLibrary = import 'gitlab-slis/library.libsonnet';
local gitalyHelper = import 'service-archetypes/helpers/gitaly.libsonnet';
local registryHelpers = import 'service-archetypes/helpers/registry.libsonnet';
local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local toolingLinks = import 'toolinglinks/toolinglinks.libsonnet';

local combined = metricsCatalog.combined;
local successCounterApdex = metricsCatalog.successCounterApdex;
local rateMetric = metricsCatalog.rateMetric;
local histogramApdex = metricsCatalog.histogramApdex;

local baseSelector = { type: 'ops-gitlab-net' };
local customRouteSLIs = registryCustomRouteSLIs.customApdexRouteConfig;

metricsCatalog.serviceDefinition({
  type: 'ops-gitlab-net',
  tier: 'sv',
  serviceIsStageless: true,

  tenants: ['gitlab-ops'],

  tags: ['golang', 'rails', 'cloud-sql', 'kube_container_rss'],

  monitoringThresholds: {
    apdexScore: 0.998,
    errorRatio: 0.999,
  },
  otherThresholds: {},
  serviceDependencies: {},

  provisioning: {
    vms: false,
    kubernetes: true,
  },
  regional: false,

  kubeConfig: {},
  kubeResources: {
    webservice: {
      kind: 'Deployment',
      containers: [
        'gitlab-workhorse',
        'webservice',
      ],
    },
    gitaly: {
      kind: 'StatefulSet',
      containers: [
        'gitaly',
      ],
    },
    kas: {
      kind: 'Deployment',
      containers: [
        'kas',
      ],
    },
    registry: {
      kind: 'Deployment',
      containers: [
        'registry',
      ],
    },
    sidekiq: {
      kind: 'Deployment',
      containers: [
        'sidekiq',
      ],
    },
  },

  recordingRuleMetrics: [
    // this is using the same recording rule metrics as we do for Sidekiq.
    // those get recorded in rules/autogenerated-key-metrics-sidekiq.yml
  ],

  local sliCommon = {
    userImpacting: true,
    team: 'reliability_foundations',
    severity: 's3',  // don't page the EOC yet
  },

  serviceLevelIndicators: {

    // webservice
    puma: sliCommon {
      description: |||
        Aggregation of most web requests that pass through the puma to the GitLab rails monolith.
        Healthchecks are excluded.
      |||,

      local railsSelector = baseSelector { job: 'gitlab-rails' },

      apdex: successCounterApdex(
        successRateMetric='gitlab_sli_rails_request_apdex_success_total',
        operationRateMetric='gitlab_sli_rails_request_apdex_total',
        selector=railsSelector,
      ),

      requestRate: rateMetric(
        counter='http_requests_total',
        selector=railsSelector,
      ),

      errorRate: rateMetric(
        counter='http_requests_total',
        selector=railsSelector { status: { re: '5..' } }
      ),

      significantLabels: [],

      toolingLinks: [
        toolingLinks.kibana(title='Puma', index='rails_ops', slowRequestSeconds=10, includeMatchersForPrometheusSelector=false),
      ],
    },

    workhorse: sliCommon {
      featureCategory: 'not_owned',
      description: |||
        Aggregation of most web requests that pass through workhorse, monitored via the HTTP interface.
        Excludes health, readiness and liveness requests. Some known slow requests, such as HTTP uploads,
        are excluded from the apdex score.
      |||,

      monitoringThresholds+: {
        errorRatio: 0.995,
      },

      local workhorseWebSelector = baseSelector { job: 'gitlab-workhorse' },

      apdex: histogramApdex(
        histogram='gitlab_workhorse_http_request_duration_seconds_bucket',
        selector=workhorseWebSelector {
          route: {
            ne: [
              '^/([^/]+/){1,}[^/]+/uploads\\\\z',
              '^/-/health$',
              '^/-/(readiness|liveness)$',
              '^/([^/]+/){1,}[^/]+\\\\.git/git-receive-pack\\\\z',
              '^/([^/]+/){1,}[^/]+\\\\.git/git-upload-pack\\\\z',
              '^/([^/]+/){1,}[^/]+\\\\.git/info/refs\\\\z',
              '^/([^/]+/){1,}[^/]+\\\\.git/gitlab-lfs/objects/([0-9a-f]{64})/([0-9]+)\\\\z',
              '^/-/cable\\\\z',
              '^/api/v4/jobs/request\\\\z',
            ],
          },
        },
        satisfiedThreshold=1,
        toleratedThreshold=10
      ),

      requestRate: rateMetric(
        counter='gitlab_workhorse_http_requests_total',
        selector=workhorseWebSelector,
      ),

      errorRate: rateMetric(
        counter='gitlab_workhorse_http_requests_total',
        selector=workhorseWebSelector {
          code: { re: '^5.*' },
          route: { ne: ['^/-/health$', '^/-/(readiness|liveness)$'] },
        },
      ),

      significantLabels: ['route'],

      toolingLinks: [
        toolingLinks.kibana(title='Workhorse', index='workhorse_ops', slowRequestSeconds=10, includeMatchersForPrometheusSelector=false),
      ],
    },

    // gitaly
    goserver: sliCommon {
      featureCategory: 'gitaly',
      description: |||
        This SLI monitors all Gitaly GRPC requests in aggregate, excluding the OperationService.
        GRPC failures which are considered to be the "server's fault" are counted as errors.
        The apdex score is based on a subset of GRPC methods which are expected to be fast.
      |||,

      local gitalyBaseSelector = baseSelector { job: 'gitaly' },

      local apdexSelector = gitalyBaseSelector {
        grpc_service: { ne: ['gitaly.OperationService'] },
      },
      local mainApdexSelector = apdexSelector {
        grpc_method: { noneOf: gitalyHelper.gitalyApdexIgnoredMethods + gitalyHelper.gitalyApdexSlowMethods },
      },
      local slowMethodApdexSelector = apdexSelector {
        grpc_method: { oneOf: gitalyHelper.gitalyApdexSlowMethods },
      },
      local operationServiceApdexSelector = gitalyBaseSelector {
        grpc_service: ['gitaly.OperationService'],
      },

      apdex: combined(
        [
          gitalyHelper.grpcServiceApdex(mainApdexSelector),
          gitalyHelper.grpcServiceApdex(slowMethodApdexSelector, satisfiedThreshold=10, toleratedThreshold=30),
          gitalyHelper.grpcServiceApdex(operationServiceApdexSelector, satisfiedThreshold=10, toleratedThreshold=30),
        ]
      ),

      requestRate: rateMetric(
        counter='gitaly_service_client_requests_total',
        selector=gitalyBaseSelector
      ),

      errorRate: gitalyHelper.gitalyGRPCErrorRate(gitalyBaseSelector),

      significantLabels: [],

      toolingLinks: [
        toolingLinks.kibana(title='Gitaly', index='gitaly_ops', slowRequestSeconds=1, includeMatchersForPrometheusSelector=false),
      ],
    },

    local sidekiqBaseSelector = baseSelector { job: 'sidekiq' },

    // registry
    registry_server: sliCommon {
      description: |||
        Aggregation of all registry HTTP requests.
      |||,

      local registryBaseSelector = baseSelector { job: 'gitlab-registry' },

      apdex: registryHelpers.mainApdex(registryBaseSelector, customRouteSLIs),

      requestRate: rateMetric(
        counter='registry_http_requests_total',
        selector=registryBaseSelector,
      ),

      errorRate: rateMetric(
        counter='registry_http_requests_total',
        selector=registryBaseSelector { code: { re: '5..' } }
      ),

      significantLabels: ['route', 'method'],

      toolingLinks: [
        toolingLinks.kibana(title='Registry', index='registry_ops', slowRequestSeconds=10, includeMatchersForPrometheusSelector=false),
      ],
    },

    // git over SSH
    gitlab_sshd: sliCommon {
      featureCategory: 'source_code_management',
      description: |||
        Monitors Gitlab-sshd, using the connections bucket, and http requests bucket.
      |||,

      local gitlabSshdBaseSelector = baseSelector { job: 'gitlab-shell' },

      apdex: histogramApdex(
        histogram='gitlab_shell_sshd_session_established_duration_seconds_bucket',
        selector=gitlabSshdBaseSelector,
        satisfiedThreshold=1,
        toleratedThreshold=5
      ),

      errorRate: rateMetric(
        counter='gitlab_sli:shell_sshd_sessions:errors_total',
        selector=gitlabSshdBaseSelector
      ),

      requestRate: rateMetric(
        counter='gitlab_sli:shell_sshd_sessions:total',
        selector=gitlabSshdBaseSelector
      ),

      significantLabels: [],

      toolingLinks: [
        toolingLinks.kibana(title='GitLab Shell', index='shell_ops', includeMatchersForPrometheusSelector=false),
      ],
    },

    // rails <-> DB
    rails_sql: sliCommon {
      upscaleLongerBurnRates: true,

      description: |||
        Represents all SQL transactions issued through ActiveRecord from the Rails monolith (web, api, websockets, but not sidekiq) to the database.
        Durations can be impacted by various conditions other than the database, including Ruby thread contention and network conditions.
      |||,

      local sqlBaseSelector = baseSelector { job: { ne: 'sidekiq' } },

      apdex: histogramApdex(
        histogram='gitlab_sql_primary_duration_seconds_bucket',
        selector=sqlBaseSelector,
        satisfiedThreshold=0.1,
        toleratedThreshold=0.25,
      ),

      requestRate: rateMetric(
        counter='gitlab_sql_primary_duration_seconds_bucket',
        selector=sqlBaseSelector { le: '+Inf' },
      ),

      significantLabels: ['feature_category'],
    },
  } + sliLibrary.get('sidekiq_execution').generateServiceLevelIndicator(baseSelector, sliCommon {
    featureCategory: 'not_owned',
    toolingLinks: [
      toolingLinks.kibana(title='Sidekiq execution', index='sidekiq_execution_ops', includeMatchersForPrometheusSelector=false),
    ],
  }) + sliLibrary.get('sidekiq_queueing').generateServiceLevelIndicator(baseSelector, sliCommon {
    featureCategory: 'not_owned',
    toolingLinks: [
      toolingLinks.kibana(title='Sidekiq queueing', index='sidekiq_queueing_ops', includeMatchersForPrometheusSelector=false),
    ],
  }),

  skippedMaturityCriteria: {
    'Service exists in the dependency graph': 'ops.gitlab.net is a standalone GitLab deployment',
  },
})
