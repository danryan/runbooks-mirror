local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;
local customRateQuery = metricsCatalog.customRateQuery;
local toolingLinks = import 'toolinglinks/toolinglinks.libsonnet';
local haproxyComponents = import './lib/haproxy_components.libsonnet';

metricsCatalog.serviceDefinition({
  type: 'git',
  tier: 'sv',
  contractualThresholds: {
    apdexRatio: 0.95,
    errorRatio: 0.005,
  },
  monitoringThresholds: {
    apdexScore: 0.9995,
    errorRatio: 0.9995,
  },
  // Deployment thresholds are optional, and when they are specified, they are
  // measured against the same multi-burn-rates as the monitoring indicators.
  // When a service is in violation, deployments may be blocked or may be rolled
  // back.
  deploymentThresholds: {
    apdexScore: 0.9995,
    errorRatio: 0.9995,
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
  components: {
    loadbalancer: haproxyComponents.haproxyHTTPLoadBalancer(
      stageMappings={
        main: { backends: ['https_git', 'websockets'], toolingLinks: [] },
        cny: { backends: ['canary_https_git'], toolingLinks: [] },  // What happens to cny websocket traffic?
      },
      selector={ type: 'frontend' },
    ),

    loadbalancer_ssh: haproxyComponents.haproxyL4LoadBalancer(
      stageMappings={
        main: { backends: ['ssh', 'altssh'], toolingLinks: [] },
        // No canary SSH for now
      },
      selector={ type: 'frontend' },
    ),

    workhorse: {
      local baseSelector = {
        job: 'gitlab-workhorse-git',
        type: 'git',
        route: [{ ne: '^/-/health$' }, { ne: '^/-/(readiness|liveness)$' }],
      },

      apdex: histogramApdex(
        histogram='gitlab_workhorse_http_request_duration_seconds_bucket',
        selector=baseSelector {
          route+: [{
            ne: '^/([^/]+/){1,}[^/]+/-/jobs/[0-9]+/terminal.ws\\\\z',
          }, {
            ne: '^/([^/]+/){1,}[^/]+/-/environments/[0-9]+/terminal.ws\\\\z',
          }],
        },
        satisfiedThreshold=30,
        toleratedThreshold=60
      ),

      requestRate: rateMetric(
        counter='gitlab_workhorse_http_requests_total',
        selector=baseSelector
      ),

      errorRate: rateMetric(
        counter='gitlab_workhorse_http_requests_total',
        selector=baseSelector {
          code: { re: '^5.*' },
        }
      ),

      significantLabels: ['fqdn', 'route'],

      toolingLinks: [
        toolingLinks.continuousProfiler(service='workhorse-git'),
        toolingLinks.sentry(slug='gitlab/gitlab-workhorse-gitlabcom'),
        toolingLinks.kibana(title='Workhorse', index='workhorse', type='git', slowRequestSeconds=10),
      ],
    },

    puma: {
      local baseSelector = { job: 'gitlab-rails', type: 'git' },
      apdex: histogramApdex(
        histogram='http_request_duration_seconds_bucket',
        selector=baseSelector,
        satisfiedThreshold=1,
        toleratedThreshold=10
      ),

      requestRate: rateMetric(
        counter='http_request_duration_seconds_count',
        selector=baseSelector
      ),

      errorRate: rateMetric(
        counter='http_request_duration_seconds_count',
        selector=baseSelector { status: { re: '5..' } }
      ),

      significantLabels: ['fqdn', 'method'],

      toolingLinks: [
        // Improve sentry link once https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/532 arrives
        toolingLinks.sentry(slug='gitlab/gitlabcom'),
        toolingLinks.kibana(title='Rails', index='rails', type='git', slowRequestSeconds=10),
      ],
    },

    gitlab_shell: {
      staticLabels: {
        tier: 'sv',
        stage: 'main',
      },

      // Unfortunately we don't have a better way of measuring this at present,
      // so we rely on HAProxy metrics
      requestRate: customRateQuery(|||
        sum by (environment) (haproxy_backend_current_session_rate{backend=~"ssh|altssh"})
      |||),

      significantLabels: [],

      toolingLinks: [
        toolingLinks.kibana(title='GitLab Shell', index='shell'),
      ],
    },
  },
})
