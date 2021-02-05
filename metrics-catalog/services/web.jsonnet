local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;
local toolingLinks = import 'toolinglinks/toolinglinks.libsonnet';
local haproxyComponents = import './lib/haproxy_components.libsonnet';
local perFeatureCategoryRecordingRules = (import './lib/puma-per-feature-category-recording-rules.libsonnet').perFeatureCategoryRecordingRules;

metricsCatalog.serviceDefinition({
  type: 'web',
  tier: 'sv',
  contractualThresholds: {
    apdexRatio: 0.95,
    errorRatio: 0.005,
  },
  monitoringThresholds: {
    apdexScore: 0.998,
    errorRatio: 0.9999,
  },
  // Deployment thresholds are optional, and when they are specified, they are
  // measured against the same multi-burn-rates as the monitoring indicators.
  // When a service is in violation, deployments may be blocked or may be rolled
  // back.
  deploymentThresholds: {
    apdexScore: 0.998,
    errorRatio: 0.9999,
  },
  serviceDependencies: {
    gitaly: true,
    'redis-sidekiq': true,
    'redis-cache': true,
    redis: true,
    patroni: true,
    pgbouncer: true,
    praefect: true,
  },
  recordingRuleMetrics: [
    'http_requests_total',
  ],
  serviceLevelIndicators: {
    loadbalancer: haproxyComponents.haproxyHTTPLoadBalancer(
      userImpacting=true,
      featureCategory='not_owned',
      team='sre_coreinfra',
      stageMappings={
        main: { backends: ['web'], toolingLinks: [] },  // What to do with `429_slow_down`?
        cny: { backends: ['canary_web'], toolingLinks: [] },
      },
      selector={ type: 'frontend' },
    ),

    workhorse: {
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
        selector={
          job: 'gitlab-workhorse-web',
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
            ],
          },
        },
        satisfiedThreshold=1,
        toleratedThreshold=10
      ),

      requestRate: rateMetric(
        counter='gitlab_workhorse_http_requests_total',
        selector='job="gitlab-workhorse-web", type="web"'
      ),

      errorRate: rateMetric(
        counter='gitlab_workhorse_http_requests_total',
        selector='job="gitlab-workhorse-web", type="web", code=~"^5.*", route!="^/-/health$", route!="^/-/(readiness|liveness)$"'
      ),

      significantLabels: ['fqdn', 'route'],

      toolingLinks: [
        toolingLinks.continuousProfiler(service='workhorse-web'),
        toolingLinks.sentry(slug='gitlab/gitlab-workhorse-gitlabcom'),
        toolingLinks.kibana(title='Workhorse', index='workhorse', type='web', slowRequestSeconds=10),
      ],
    },

    imagescaler: {
      userImpacting: false,
      featureCategory: 'users',
      description: |||
        The imagescaler rescales images before sending them to clients. This allows faster transmission of
        images and faster rendering of web pages.
      |||,

      apdex: histogramApdex(
        histogram='gitlab_workhorse_image_resize_duration_seconds_bucket',
        selector='job="gitlab-workhorse-web", type="web"',
        satisfiedThreshold=0.2,
        toleratedThreshold=0.8
      ),

      requestRate: rateMetric(
        counter='gitlab_workhorse_image_resize_requests_total',
        selector='job="gitlab-workhorse-web", type="web"'
      ),

      // TODO: remove status!="unknown" from this selector after 1 December 2020
      // See https://gitlab.com/gitlab-com/gl-infra/infrastructure/-/issues/11903 for details
      errorRate: rateMetric(
        counter='gitlab_workhorse_image_resize_requests_total',
        selector='job="gitlab-workhorse-web", type="web", status!="success", status!="unknown", status!="success-client-cache"'
      ),

      significantLabels: ['fqdn'],
    },

    puma: {
      userImpacting: true,
      featureCategory: 'not_owned',
      team: 'sre_coreinfra',
      description: |||
        Aggregation of most web requests that pass through the puma to the GitLab rails monolith.
        Healthchecks are excluded.
      |||,

      local baseSelector = { job: 'gitlab-rails', type: 'web' },
      apdex: histogramApdex(
        histogram='http_request_duration_seconds_bucket',
        selector=baseSelector,
        satisfiedThreshold=1,
        toleratedThreshold=10
      ),

      requestRate: rateMetric(
        counter='http_requests_total',
        selector=baseSelector,
      ),

      errorRate: rateMetric(
        counter='http_requests_total',
        selector=baseSelector { status: { re: '5..' } }
      ),

      significantLabels: ['fqdn', 'method', 'feature_category'],

      toolingLinks: [
        // Improve sentry link once https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/532 arrives
        toolingLinks.sentry(slug='gitlab/gitlabcom'),
        toolingLinks.kibana(title='Rails', index='rails', type='web', slowRequestSeconds=10),
      ],
    },
  },
  // Special per-feature-category recording rules
  extraRecordingRulesPerBurnRate: [
    // Adds per-feature-category plus error rates across multiple burn rates
    perFeatureCategoryRecordingRules({ type: 'web' }),
  ],
})
