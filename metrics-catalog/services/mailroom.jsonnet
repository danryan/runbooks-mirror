local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local rateMetric = metricsCatalog.rateMetric;
local toolingLinks = import 'toolinglinks/toolinglinks.libsonnet';
local kubeLabelSelectors = metricsCatalog.kubeLabelSelectors;

metricsCatalog.serviceDefinition({
  type: 'mailroom',
  tier: 'sv',
  serviceIsStageless: true,  // mailroom does not have a cny stage
  monitoringThresholds: {
    errorRatio: 0.9995,
  },
  serviceDependencies: {
    patroni: true,
    pgbouncer: true,
    consul: true,
  },
  provisioning: {
    kubernetes: true,
    vms: false,
  },
  kubeConfig: {
    labelSelectors: kubeLabelSelectors(
      ingressSelector=null  // no ingress for logging
    ),
  },
  kubeResources: {
    mailroom: {
      kind: 'Deployment',
      containers: [
        'mailroom',
      ],
    },
  },
  serviceLevelIndicators: {
    local mailWorkers = ['EmailReceiverWorker', 'ServiceDeskEmailReceiverWorker'],
    local workerSelector = { worker: { oneOf: mailWorkers } },
    emailsProcessed: {
      userImpacting: true,
      featureCategory: 'not_owned',

      // Avoid long burn rates on Sidekiq metrics...
      upscaleLongerBurnRates: true,

      description: |||
        Monitors incoming emails delivered from the imap inbox and processed through Sidekiq's `EmailReceiverWorker`.
        Note that since Mailroom has poor observability, we use Sidekiq metrics for this, and this could lead to certain Sidekiq problems
        being attributed to Mailroom
      |||,

      requestRate: rateMetric(
        counter='gitlab_sli_sidekiq_execution_total',
        selector=workerSelector,
      ),

      errorRate: rateMetric(
        counter='gitlab_sli_sidekiq_execution_error_total',
        selector=workerSelector,
      ),

      emittedBy: ['ops-gitlab-net', 'sidekiq'],

      significantLabels: [],

      toolingLinks: [
        toolingLinks.kibana(title='Mailroom', index='mailroom', includeMatchersForPrometheusSelector=false),
        toolingLinks.kibana(
          title='Sidekiq receiver workers',
          index='sidekiq',
          includeMatchersForPrometheusSelector=false,
          matches={ 'json.class': mailWorkers }
        ),
      ],
    },
    email_receiver: {
      userImpacting: true,
      severity: 's3',
      featureCategory: 'service_desk',
      team: 'product_planning',
      description: |||
        Monitors ratio between all received emails and received emails which
        could not be processed for some reason. This is different from just the sidekiq
        jobs in `emailsProcessed` as it uses specific errors to measure errors rather than
        job failures.
      |||,

      requestRate: rateMetric(
        counter='gitlab_sli_sidekiq_execution_total',
        selector=workerSelector
      ),

      errorRate: rateMetric(
        counter='gitlab_transaction_event_email_receiver_error_total',
        selector={ 'error': { ne: 'Gitlab::Email::AutoGeneratedEmailError' } }
      ),

      emittedBy: ['ops-gitlab-net', 'sidekiq'],

      monitoringThresholds+: {
        errorRatio: 0.7,
      },

      significantLabels: [],

      toolingLinks: [
        toolingLinks.kibana(title='Email receiver errors', index='sidekiq', type='sidekiq', message='Error processing message'),
      ],
    },
  },
})
