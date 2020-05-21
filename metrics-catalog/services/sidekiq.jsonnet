local metricsCatalog = import '../lib/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;
local combined = metricsCatalog.combined;
local sidekiqHelpers = import './lib/sidekiq-helpers.libsonnet';

{
  type: 'sidekiq',
  tier: 'sv',
  monitoringThresholds: {
    apdexRatio: 0.95,
    errorRatio: 0.05,
  },
  serviceDependencies: {
    gitaly: true,
    'redis-sidekiq': true,
    'redis-cache': true,
    redis: true,
    patroni: true,
    pgbouncer: true,
    nfs: true,
    praefect: true,
  },
  components: {
    shard_urgent_other: {
      apdex: combined([
        histogramApdex(
          histogram='sidekiq_jobs_completion_seconds_bucket',
          selector='urgency="high", shard="urgent-other"',
          satisfiedThreshold=sidekiqHelpers.slos.urgent.executionDurationSeconds,
        ),
        histogramApdex(
          histogram='sidekiq_jobs_queue_duration_seconds_bucket',
          selector='urgency="high", shard="urgent-other"',
          satisfiedThreshold=sidekiqHelpers.slos.urgent.queueingDurationSeconds,
        ),
        histogramApdex(
          histogram='sidekiq_jobs_completion_seconds_bucket',
          selector='urgency="low", shard="urgent-other"',
          satisfiedThreshold=sidekiqHelpers.slos.lowUrgency.executionDurationSeconds,
        ),
        histogramApdex(
          histogram='sidekiq_jobs_queue_duration_seconds_bucket',
          selector='urgency="low", shard="urgent-other"',
          satisfiedThreshold=sidekiqHelpers.slos.lowUrgency.queueingDurationSeconds,
        ),
        histogramApdex(
          histogram='sidekiq_jobs_completion_seconds_bucket',
          selector='urgency="throttled", shard="urgent-other"',
          satisfiedThreshold=sidekiqHelpers.slos.throttled.executionDurationSeconds,
        )
      ]),

      requestRate: rateMetric(
        counter='sidekiq_jobs_completion_seconds_bucket',
          selector='shard="urgent_other"',
      ),

      errorRate: rateMetric(
        counter='sidekiq_jobs_failed_total',
        selector='urgency="high"'
      ),

      significantLabels: ['fqdn'],
    },

    high_urgency_job_execution: {
      apdex: histogramApdex(
        histogram='sidekiq_jobs_completion_seconds_bucket',
        selector='urgency="high"',
        satisfiedThreshold=sidekiqHelpers.slos.urgent.executionDurationSeconds,
      ),

      requestRate: rateMetric(
        counter='sidekiq_jobs_completion_seconds_bucket',
        selector='urgency="high",le="+Inf"'
      ),

      errorRate: rateMetric(
        counter='sidekiq_jobs_failed_total',
        selector='urgency="high"'
      ),

      significantLabels: ['shard'],
    },

    high_urgency_job_queueing: {
      apdex: histogramApdex(
        histogram='sidekiq_jobs_queue_duration_seconds_bucket',
        selector='urgency="high"',
        satisfiedThreshold=sidekiqHelpers.slos.urgent.queueingDurationSeconds,
      ),

      requestRate: rateMetric(
        counter='sidekiq_enqueued_jobs_total',
        selector='urgency="high"'
      ),

      significantLabels: ['shard'],
    },

    low_urgency_job_execution: {
      apdex: histogramApdex(
        histogram='sidekiq_jobs_completion_seconds_bucket',
        selector='urgency="low"',
        satisfiedThreshold=sidekiqHelpers.slos.lowUrgency.executionDurationSeconds,
      ),

      requestRate: rateMetric(
        counter='sidekiq_jobs_completion_seconds_bucket',
        selector='urgency="low",le="+Inf"'
      ),

      errorRate: rateMetric(
        counter='sidekiq_jobs_failed_total',
        selector='urgency="low"'
      ),

      significantLabels: ['shard'],
    },

    low_urgency_job_queueing: {
      apdex: histogramApdex(
        histogram='sidekiq_jobs_queue_duration_seconds_bucket',
        selector='urgency="low"',
        satisfiedThreshold=sidekiqHelpers.slos.lowUrgency.queueingDurationSeconds,
      ),

      requestRate: rateMetric(
        counter='sidekiq_enqueued_jobs_total',
        selector='urgency="low"'
      ),

      significantLabels: ['shard'],
    },

    throttled_job_execution: {
      apdex: histogramApdex(
        histogram='sidekiq_jobs_completion_seconds_bucket',
        selector='urgency="throttled"',
        satisfiedThreshold=sidekiqHelpers.slos.throttled.executionDurationSeconds,
      ),

      requestRate: rateMetric(
        counter='sidekiq_jobs_completion_seconds_bucket',
        selector='urgency="throttled",le="+Inf"'
      ),

      errorRate: rateMetric(
        counter='sidekiq_jobs_failed_total',
        selector='urgency="throttled"'
      ),

      significantLabels: ['shard'],
    },

    throttled_job_queueing: {
      requestRate: rateMetric(
        counter='sidekiq_enqueued_jobs_total',
        selector='urgency="throttled"'
      ),

      significantLabels: ['shard'],
    },
  },

  saturationTypes: [
    'cpu',
    'disk_space',
    'memory',
    'open_fds',
    'sidekiq_workers',
    'single_node_cpu',
    'single_node_puma_workers',
    'single_node_unicorn_workers',
    'workers',
  ],
}
