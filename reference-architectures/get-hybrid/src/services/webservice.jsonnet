local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;
local kubeLabelSelectors = metricsCatalog.kubeLabelSelectors;

metricsCatalog.serviceDefinition({
  type: 'webservice',
  tier: 'sv',

  tags: ['golang'],

  monitoringThresholds: {
    apdexScore: 0.998,
    errorRatio: 0.9999,
  },

  otherThresholds: {},
  serviceDependencies: {},
  // recordingRuleMetrics: [
  //   'http_requests_total',
  // ],
  provisioning: {
    vms: false,
    kubernetes: true,
  },
  regional: false,
  kubeConfig: {
    local kubeSelector = { app: 'webservice' },
    labelSelectors: kubeLabelSelectors(
      podSelector=kubeSelector,
      hpaSelector=kubeSelector,
      nodeSelector={ eks_amazonaws_com_nodegroup: 'gitlab_webservice_pool' },
      ingressSelector=kubeSelector,
      deploymentSelector=kubeSelector
    ),
  },
  kubeResources: {
    'gitlab-webservice-default': {
      kind: 'Deployment',
      containers: [
        'gitlab-workhorse',
        'webservice',
      ],
    },
  },
  serviceLevelIndicators: {
    puma: {
      userImpacting: true,
      description: |||
        Aggregation of most web requests that pass through the puma to the GitLab rails monolith.
        Healthchecks are excluded.
      |||,

      local baseSelector = { job: 'gitlab-rails' },
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

      significantLabels: [],

      toolingLinks: [],
    },

    local workhorseSelector = {
      route: {
        ne: [
          '^/-/health$',
          '^/-/(readiness|liveness)$',
        ],
      },
    },
    workhorse: {
      userImpacting: true,
      featureCategory: 'not_owned',
      description: |||
        Aggregation of most web requests that pass through workhorse, monitored via the HTTP interface.
        Excludes health, readiness and liveness requests. Some known slow requests, such as HTTP uploads,
        are excluded from the apdex score.
      |||,

      apdex: histogramApdex(
        histogram='gitlab_workhorse_http_request_duration_seconds_bucket',
        selector=workhorseSelector {
          route+: {
            ne+: [
              '^/([^/]+/){1,}[^/]+/uploads\\\\z',
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
        selector=workhorseSelector,
      ),

      errorRate: rateMetric(
        counter='gitlab_workhorse_http_requests_total',
        selector=workhorseSelector {
          code: { re: '^5.*' },
        },
      ),

      significantLabels: ['route'],

      toolingLinks: [],
    },
  },

  extraRecordingRulesPerBurnRate: [],
})