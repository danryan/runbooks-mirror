local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;
local toolingLinks = import 'toolinglinks/toolinglinks.libsonnet';
local haproxyComponents = import './lib/haproxy_components.libsonnet';
local sliLibrary = import 'gitlab-slis/library.libsonnet';
local serviceLevelIndicatorDefinition = import 'servicemetrics/service_level_indicator_definition.libsonnet';
local kubeLabelSelectors = metricsCatalog.kubeLabelSelectors;
local dependOnPatroni = import 'inhibit-rules/depend_on_patroni.libsonnet';
local dependOnRedisSidekiq = import 'inhibit-rules/depend_on_redis_sidekiq.libsonnet';

local railsSelector = { job: 'gitlab-rails', type: 'web' };

metricsCatalog.serviceDefinition({
  type: 'web',
  tier: 'sv',
  tenants: ['gitlab-gprd', 'gitlab-gstg', 'gitlab-pre'],

  tags: ['golang', 'rails', 'puma', 'kube_container_rss'],

  contractualThresholds: {
    apdexRatio: 0.9,
    errorRatio: 0.005,
  },
  monitoringThresholds: {
    apdexScore: 0.998,
    errorRatio: 0.9999,
  },
  otherThresholds: {
    // Deployment thresholds are optional, and when they are specified, they are
    // measured against the same multi-burn-rates as the monitoring indicators.
    // When a service is in violation, deployments may be blocked or may be rolled
    // back.
    deployment: {
      apdexScore: 0.998,
      errorRatio: 0.9999,
    },

    mtbf: {
      apdexScore: 0.9993,
      errorRatio: 0.99995,
    },
  },
  serviceDependencies: {
    clickhouse: true,
    gitaly: true,
    'redis-cluster-ratelimiting': true,
    'redis-cluster-cache': true,
    'redis-cluster-shared-state': true,
    'redis-cluster-chat-cache': true,
    'redis-cluster-feature-flag': true,
    'redis-cluster-queues-meta': true,
    'redis-cluster-repo-cache': true,
    'redis-sidekiq': true,
    'redis-sessions': true,
    'redis-db-load-balancing': true,
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
  recordingRuleMetrics: [
    'http_requests_total',
  ] + (
    sliLibrary.get('rails_request').recordingRuleMetrics
    + sliLibrary.get('global_search').recordingRuleMetrics
  ),
  provisioning: {
    vms: false,
    kubernetes: true,
  },
  regional: true,
  kubeResources: {
    web: {
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
        main: { backends: ['web', 'main_web'], toolingLinks: [] },  // What to do with `429_slow_down`?
        cny: { backends: ['canary_web'], toolingLinks: [] },
      },
      selector={ type: 'frontend' },
      regional=false,
      dependsOn=dependOnPatroni.sqlComponents + dependOnRedisSidekiq.railsClientComponents,
    ),

    local workhorseWebSelector = { job: { re: 'gitlab-workhorse|gitlab-workhorse-web' }, type: 'web' },
    workhorse: {
      serviceAggregation: false,
      userImpacting: true,
      featureCategory: 'not_owned',
      team: 'workhorse',
      description: |||
        Aggregation of most web requests that pass through workhorse, monitored via the HTTP interface.
        Excludes health, readiness and liveness requests. Some known slow requests, such as HTTP uploads,
        are excluded from the apdex score.
      |||,

      apdex: histogramApdex(
        histogram='gitlab_workhorse_http_request_duration_seconds_bucket',
        selector=workhorseWebSelector {
          route: {
            ne: [
              '^/([^/]+/){1,}[^/]+/uploads\\\\z',
              '^/-/health$',
              '^/-/(readiness|liveness)$',
              // Technically none of these git endpoints should end up in cny, but sometimes they do,
              // so exclude them from apdex
              '^/([^/]+/){1,}[^/]+\\\\.git/git-receive-pack\\\\z',
              '^/([^/]+/){1,}[^/]+\\\\.git/git-upload-pack\\\\z',
              '^/([^/]+/){1,}[^/]+\\\\.git/info/refs\\\\z',
              '^/([^/]+/){1,}[^/]+\\\\.git/gitlab-lfs/objects/([0-9a-f]{64})/([0-9]+)\\\\z',
              '^/.+\\\\.git/git-receive-pack\\\\z',  // ^/.+\.git/git-receive-pack\z
              '^/.+\\\\.git/git-upload-pack\\\\z',  // ^/.+\.git/git-upload-pack\z
              '^/.+\\\\.git/info/refs\\\\z',  // ^/.+\.git/info/refs\z
              '^/.+\\\\.git/gitlab-lfs/objects/([0-9a-f]{64})/([0-9]+)\\\\z',  // /.+\.git/gitlab-lfs/objects/([0-9a-f]{64})/([0-9]+)\z
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

      significantLabels: ['region', 'route'],

      toolingLinks: [
        toolingLinks.continuousProfiler(service='workhorse-web'),
        toolingLinks.sentry(projectId=15),
        toolingLinks.kibana(title='Workhorse', index='workhorse', type='web', slowRequestSeconds=10),
      ],

      dependsOn: dependOnPatroni.sqlComponents,
    },

    imagescaler: {
      serviceAggregation: false,
      userImpacting: false,
      featureCategory: 'user_profile',
      description: |||
        The imagescaler rescales images before sending them to clients. This allows faster transmission of
        images and faster rendering of web pages.
      |||,

      apdex: histogramApdex(
        histogram='gitlab_workhorse_image_resize_duration_seconds_bucket',
        selector=workhorseWebSelector,
        satisfiedThreshold=0.4,
        toleratedThreshold=0.8
      ),

      requestRate: rateMetric(
        counter='gitlab_workhorse_image_resize_requests_total',
        selector=workhorseWebSelector,
      ),

      significantLabels: ['region'],

      toolingLinks: [
        toolingLinks.kibana(title='Image Resizer', index='workhorse_imageresizer', type='web'),
      ],
    },

    logins: {
      monitoringThresholds+: {
        errorRatio: 0.99,
      },
      severity: 's3',
      serviceAggregation: false,
      userImpacting: true,
      featureCategory: 'system_access',
      description: |||
        Measures Logins as the number of successful Logins vs the number of initated attempts.

        An alert on this SLI may indicate that users are unable to login to GitLab.
      |||,

      requestRate: rateMetric(
        counter='gitlab_sli_rails_request_total',
        selector={ endpoint_id: { re: '.*OmniauthCallbacksController.*|SessionsController#create', nre: '.*#failure' } },
      ),

      errorRate: rateMetric(
        counter='gitlab_sli_rails_request_error_total',
        selector={ endpoint_id: { re: '.*OmniauthCallbacksController.*|SessionsController#create' } },
      ),

      significantLabels: ['endpoint_id'],

      toolingLinks: [],
    },

    dependency_proxy: {
      severity: 's3',
      serviceAggregation: false,
      userImpacting: true,
      featureCategory: 'virtual_registry',
      description: |||
        Measures calls to Dependency Proxy as the number of unsuccessful calls vs the number of total calls.

        An alert on this SLI may indicate that pulling images from the container registry takes longer than expected or fails outright.
      |||,

      local depencencyProxySelector = { endpoint_id: { re: 'Groups::DependencyProxyForContainersController.*' } },
      requestRate: rateMetric(
        counter='gitlab_sli_rails_request_total',
        selector=depencencyProxySelector,
      ),

      errorRate: rateMetric(
        counter='gitlab_sli_rails_request_error_total',
        selector=depencencyProxySelector,
      ),

      significantLabels: ['endpoint_id'],

      toolingLinks: [
        toolingLinks.kibana(
          title='Rails',
          index='rails',
          matches={ 'json.meta.caller_id': 'Groups::DependencyProxyForContainersController' }
        ),
      ],
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
        Measures calls to the Groups web resource as the number of unsuccessful calls vs the number of total calls.

        An alert on this SLI may indicate that users are unable to modify or create groups via the web.
      |||,

      local endpointIds = ['GroupsController#create', 'GroupsController#update'],
      local groupManagementSelector = { endpoint_id: { oneOf: endpointIds }, type: 'web' },

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
    toolingLinks: [
      toolingLinks.kibana(title='Rails', index='rails'),
    ],
    dependsOn: dependOnPatroni.sqlComponents,
  }) + sliLibrary.get('global_search').generateServiceLevelIndicator(railsSelector, {
    serviceAggregation: false,  // Don't add this to the request rate of the service
    severity: 's3',  // Don't page SREs for this SLI
  }),
})
