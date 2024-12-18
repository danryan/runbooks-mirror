local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;
local toolingLinks = import 'toolinglinks/toolinglinks.libsonnet';
local haproxyComponents = import './lib/haproxy_components.libsonnet';
local sliLibrary = import 'gitlab-slis/library.libsonnet';
local serviceLevelIndicatorDefinition = import 'servicemetrics/service_level_indicator_definition.libsonnet';
local kubeLabelSelectors = metricsCatalog.kubeLabelSelectors;
local dependOnPatroni = import 'inhibit-rules/depend_on_patroni.libsonnet';

local railsSelector = { job: 'gitlab-rails', type: 'api' };

metricsCatalog.serviceDefinition({
  type: 'api',
  tier: 'sv',
  tenants: ['gitlab-gprd', 'gitlab-gstg', 'gitlab-pre'],

  tags: ['golang', 'rails', 'puma', 'kube_container_rss'],

  contractualThresholds: {
    apdexRatio: 0.9,
    errorRatio: 0.005,
  },
  monitoringThresholds: {
    apdexScore: 0.995,
    errorRatio: 0.999,
  },
  otherThresholds: {
    // Deployment thresholds are optional, and when they are specified, they are
    // measured against the same multi-burn-rates as the monitoring indicators.
    // When a service is in violation, deployments may be blocked or may be rolled
    // back.
    deployment: {
      apdexScore: 0.995,
      errorRatio: 0.999,
    },

    mtbf: {
      apdexScore: 0.9985,
      errorRatio: 0.9998,
    },
  },
  serviceDependencies: {
    gitaly: true,
    kas: true,
    'redis-cluster-ratelimiting': true,
    'redis-cluster-chat-cache': true,
    'redis-cluster-cache': true,
    'redis-cluster-shared-state': true,
    'redis-cluster-feature-flag': true,
    'redis-cluster-queues-meta': true,
    'redis-cluster-sessions': true,
    'redis-cluster-repo-cache': true,
    'redis-tracechunks': true,
    'redis-sidekiq': true,
    'redis-sessions': true,
    'redis-pubsub': true,
    redis: true,
    patroni: true,
    pgbouncer: true,
    'ext-pvs': true,
    search: true,
    consul: true,
    'google-cloud-storage': true,
    zoekt: true,
  },
  provisioning: {
    vms: false,
    kubernetes: true,
  },
  recordingRuleMetrics:
    sliLibrary.get('graphql_query').recordingRuleMetrics,
  regional: true,
  kubeResources: {
    api: {
      kind: 'Deployment',
      containers: [
        'gitlab-workhorse',
        'webservice',
      ],
    },
  },
  serviceLevelIndicators: {
    loadbalancer: haproxyComponents.haproxyHTTPLoadBalancer(
      userImpacting=true,
      featureCategory='not_owned',
      stageMappings={
        main: {
          backends: ['api', 'api_rate_limit', 'main_api'],
          toolingLinks: [
            toolingLinks.bigquery(title='Main-stage: top paths for 5xx errors', savedQuery='805818759045:342973e81d4a481d8055b43564d09728'),
          ],
        },
        cny: { backends: ['canary_api'], toolingLinks: [] },
      },
      selector={ type: 'frontend' },
      regional=false,
      dependsOn=dependOnPatroni.sqlComponents,
    ),

    nginx_ingress: {
      userImpacting: true,
      featureCategory: 'not_owned',
      description: |||
        nginx for api
      |||,

      local baseSelector = { type: 'api' },

      requestRate: rateMetric(
        counter='nginx_ingress_controller_requests:labeled',
        selector=baseSelector
      ),

      errorRate: rateMetric(
        counter='nginx_ingress_controller_requests:labeled',
        selector=baseSelector {
          status: { re: '^5.*' },
        }
      ),

      significantLabels: ['path', 'status'],

      // TODO: Add some links here
      toolingLinks: [
      ],
      serviceAggregation: false,
      dependsOn: dependOnPatroni.sqlComponents,
    },

    workhorse: {
      userImpacting: true,
      serviceAggregation: false,
      featureCategory: 'not_owned',
      team: 'workhorse',
      description: |||
        Aggregation of most web requests that pass through workhorse, monitored via the HTTP interface.
        Excludes health, readiness and liveness requests. Some known slow requests, such as HTTP uploads,
        are excluded from the apdex score.
      |||,

      local baseSelector = {
        job: { oneOf: ['gitlab-workhorse-api', 'gitlab-workhorse'] },
        type: 'api',
      },

      apdex: histogramApdex(
        histogram='gitlab_workhorse_http_request_duration_seconds_bucket',
        // Note, using `|||` avoids having to double-escape the backslashes in the selector query
        selector=baseSelector {
          route: {
            ne: [
              '\\\\A/api/v4/jobs/request\\\\z',
              '^/api/v4/jobs/request\\\\z',
              '^/-/health$',
              '^/-/(readiness|liveness)$',
            ],
          },
        },
        satisfiedThreshold=1,
        toleratedThreshold=10
      ),

      requestRate: rateMetric(
        counter='gitlab_workhorse_http_requests_total',
        selector=baseSelector
      ),

      errorRate: rateMetric(
        counter='gitlab_workhorse_http_requests_total',
        selector=baseSelector {
          code: { re: '^5.*' },
          route: {
            ne: [
              '^/-/health$',
              '^/-/(readiness|liveness)$',
            ],
          },
        },
      ),

      significantLabels: ['region', 'method', 'route'],

      toolingLinks: [
        toolingLinks.continuousProfiler(service='workhorse-api'),
        toolingLinks.sentry(projectId=15),
        toolingLinks.kibana(title='Workhorse', index='workhorse', type='api', slowRequestSeconds=10),
      ],

      dependsOn: dependOnPatroni.sqlComponents,
    },

    group_management: {
      monitoringThresholds+: {
        errorRatio: 0.999,
      },
      severity: 's3',
      serviceAggregation: false,
      userImpacting: true,
      featureCategory: 'groups_and_projects',
      description: |||
        Measures calls to the Groups API resource as the number of unsuccessful calls vs the number of total calls.

        An alert on this SLI may indicate that users are unable to modify or create groups via the API.
      |||,

      local endpointIds = ['PUT /api/:version/groups/:id', 'POST /api/:version/groups'],
      local groupManagementSelector = { endpoint_id: { oneOf: endpointIds }, type: 'api' },

      requestRate: rateMetric(
        counter='gitlab_sli_rails_request_total',
        selector=groupManagementSelector,
      ),

      errorRate: rateMetric(
        counter='gitlab_sli_rails_request_error_total',
        selector=groupManagementSelector,
      ),

      useConfidenceLevelForSLIAlerts: '98%',

      significantLabels: ['endpoint_id'],

      toolingLinks: [
        toolingLinks.kibana(
          title='Rails',
          index='rails',
          matches={ 'json.meta.caller_id': endpointIds }
        ),
      ],
    },
  } + sliLibrary.get('rails_request').generateServiceLevelIndicator(railsSelector, {
    monitoringThresholds+: {
      apdexScore: 0.99,
    },

    toolingLinks: [
      toolingLinks.kibana(title='Rails', index='rails'),
    ],
    dependsOn: dependOnPatroni.sqlComponents,
  }) + sliLibrary.get('graphql_query').generateServiceLevelIndicator(
    // graphql:unknown signifies that the graphql query came from outside the GitLab codebase,
    // eg, from an API user, or the iGraphQL Explorer. We have no control over these queries and
    // they could fail for a variety of reasons, including invalid queries, misformed graphql etc.
    // They should not be included in the SLI.
    // Invalid queries from the GitLab codebase should be included in the SLI, however.
    railsSelector { endpoint_id: { ne: 'graphql:unknown' } }, {
      useConfidenceLevelForSLIAlerts: '98%',
      serviceAggregation: false,
      toolingLinks: [
        toolingLinks.kibana(title='Rails', index='rails_graphql'),
      ],
      monitoringThresholds+: {
        // lowered from 0.9995 until https://gitlab.com/gitlab-org/gitlab/-/issues/469590
        // is resolved.
        errorRatio: 0.999,
      },
      dependsOn: dependOnPatroni.sqlComponents,
    }
  ) + sliLibrary.get('global_search').generateServiceLevelIndicator(railsSelector, {
    serviceAggregation: false,  // Don't add this to the request rate of the service
    severity: 's3',  // Don't page SREs for this SLI
  }),
  capacityPlanning: {
    components: [
      {
        name: 'ruby_thread_contention',
        parameters: {
          changepoints: [
            '2023-07-15',
          ],
        },
      },
    ],
  },
})
