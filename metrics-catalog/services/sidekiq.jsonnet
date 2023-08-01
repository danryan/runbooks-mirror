local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;
local sidekiqHelpers = import './lib/sidekiq-helpers.libsonnet';
local perWorkerRecordingRules = (import './lib/sidekiq-per-worker-recording-rules.libsonnet').perWorkerRecordingRules;
local combined = metricsCatalog.combined;
local toolingLinks = import 'toolinglinks/toolinglinks.libsonnet';
local kubeLabelSelectors = metricsCatalog.kubeLabelSelectors;
local sliLibrary = import 'gitlab-slis/library.libsonnet';

local baseSelector = { type: 'sidekiq' };
local highUrgencySelector = { urgency: 'high' };
local lowUrgencySelector = { urgency: 'low' };
local throttledUrgencySelector = { urgency: 'throttled' };

metricsCatalog.serviceDefinition({
  type: 'sidekiq',
  tier: 'sv',
  tags: ['rails'],
  shardLevelMonitoring: true,  // SLIs will inherit shard-level monitoring by default

  contractualThresholds: {
    apdexRatio: 0.9,
    errorRatio: 0.005,
  },
  monitoringThresholds: {
    apdexScore: 0.995,
    errorRatio: 0.995,
  },
  otherThresholds: {
    // Deployment thresholds are optional, and when they are specified, they are
    // measured against the same multi-burn-rates as the monitoring indicators.
    // When a service is in violation, deployments may be blocked or may be rolled
    // back.
    deployment: {
      apdexScore: 0.995,
      errorRatio: 0.995,
    },
  },
  serviceDependencies: {
    gitaly: true,
    'redis-tracechunks': true,
    'redis-sidekiq': true,
    'redis-cache': true,
    redis: true,
    patroni: true,
    pgbouncer: true,
    praefect: true,
    pvs: true,
    search: true,
    consul: true,
    'google-cloud-storage': true,
  },
  provisioning: {
    kubernetes: true,
    vms: false,
  },
  // Use recordingRuleMetrics to specify a set of metrics with known high
  // cardinality. The metrics catalog will generate recording rules with
  // the appropriate aggregations based on this set.
  // Use sparingly, and don't overuse.
  recordingRuleMetrics: [
    // TODO: Although not used here, below 3 intermediate rules are still being used in
    // mailroom, ops-gitlab-net, and various dashboards
    'sidekiq_jobs_completion_seconds_bucket',
    'sidekiq_jobs_queue_duration_seconds_bucket',
  ] + (
    sliLibrary.get('sidekiq_execution').recordingRuleMetrics
    + sliLibrary.get('sidekiq_queueing').recordingRuleMetrics
  ),
  kubeConfig: {
    labelSelectors: kubeLabelSelectors(
      ingressSelector=null,  // no ingress for sidekiq
      nodeSelector={ type: 'sidekiq' },
      // Sidekiq nodes don't present a stage label at present, so\
      // we hardcode to main stage
      nodeStaticLabels={ stage: 'main' },
    ),
  },
  kubeResources: std.foldl(
    function(memo, shard)
      memo {
        // Deployment tags follow the convention sidekiq-catchall etc
        ['sidekiq-' + shard.name]: {
          kind: 'Deployment',
          containers: [
            'sidekiq',
          ],
        },
      },
    sidekiqHelpers.shards.listAll(),
    {},
  ),
  serviceLevelIndicators: {
    email_receiver: {
      userImpacting: true,
      severity: 's3',
      featureCategory: 'service_desk',
      team: 'product_planning',
      description: |||
        Monitors ratio between all received emails and received emails which
        could not be processed for some reason.
      |||,
      shardLevelMonitoring: false,

      requestRate: rateMetric(
        counter='gitlab_sli_sidekiq_execution_apdex_total',
        selector=baseSelector { worker: { re: 'EmailReceiverWorker|ServiceDeskEmailReceiverWorker' } }
      ),

      errorRate: rateMetric(
        counter='gitlab_transaction_event_email_receiver_error_total',
        selector=baseSelector { 'error': { ne: 'Gitlab::Email::AutoGeneratedEmailError' } }
      ),

      monitoringThresholds+: {
        errorRatio: 0.7,
      },

      significantLabels: ['error'],

      toolingLinks: [
        toolingLinks.kibana(title='Email receiver errors', index='sidekiq', type='sidekiq', message='Error processing message'),
      ],
    },
  } + sliLibrary.get('global_search_indexing').generateServiceLevelIndicator(baseSelector, {
    serviceAggregation: false,  // Don't add this to the request rate of the service
    severity: 's3',  // Don't page SREs for this SLI
    shardLevelMonitoring: false,
  }) + sliLibrary.get('sidekiq_execution').generateServiceLevelIndicator(baseSelector { external_dependencies: { ne: 'yes' } }, {
    // TODO: For now, only sidekiq execution is considered towards service aggregation
    // which means queueing is not part of the service aggregation & SLA.
    // Future plan is to be able to specify either apdex, errors, or ops to be included in service aggregaiton.
    // See https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/2423.
    serviceAggregation: true,
    severity: 's2',
    toolingLinks: [
      // Improve sentry link once https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/532 arrives
      toolingLinks.sentry(slug='gitlab/gitlabcom', type='sidekiq'),
      toolingLinks.kibana(title='Sidekiq execution', index='sidekiq_execution', type='sidekiq'),
    ],
  }) + sliLibrary.get('sidekiq_queueing').generateServiceLevelIndicator(baseSelector { external_dependencies: { ne: 'yes' } }, {
    serviceAggregation: false,  // Don't add this to the request rate of the service
    severity: 's2',
    toolingLinks: [
      toolingLinks.kibana(title='Sidekiq queueing', index='sidekiq_queueing', type='sidekiq'),
    ],
    featureCategory: 'not_owned',
  }) + sliLibrary.get('sidekiq_execution_with_external_dependency').generateServiceLevelIndicator(baseSelector { external_dependencies: { eq: 'yes' } }, {
    serviceAggregation: false,  // Don't add this to the request rate of the service
    shardLevelMonitoring: false,
    severity: 's3',
    monitoringThresholds+: {
      errorRatio: 0.9,
    },
  }) + sliLibrary.get('sidekiq_queueing_with_external_dependency').generateServiceLevelIndicator(baseSelector { external_dependencies: { eq: 'yes' } }, {
    serviceAggregation: false,  // Don't add this to the request rate of the service
    shardLevelMonitoring: false,
    team: 'sre_reliability',
    severity: 's3',
  }),

  // Special per-worker recording rules
  extraRecordingRulesPerBurnRate: [
    // Adds per-work queuing/execution apdex, plus error rates etc
    // across multiple burn rates
    perWorkerRecordingRules,
  ],
  capacityPlanning: {
    components: [
      {
        name: 'rails_db_connection_pool',
        parameters: {
          changepoints: [
            '2023-04-03',  // https://gitlab.com/gitlab-com/gl-infra/capacity-planning/-/issues/993
          ],
        },
      },
    ],
  },
})
