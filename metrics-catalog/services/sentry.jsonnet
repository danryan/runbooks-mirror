local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local toolingLinks = import 'toolinglinks/toolinglinks.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;
local combined = metricsCatalog.combined;

metricsCatalog.serviceDefinition({
  type: 'sentry',
  tier: 'inf',

  tags: [
    // postgres tag implies the service is monitored with the postgres_exporter recipe from
    // https://gitlab.com/gitlab-cookbooks/gitlab-exporters
    'postgres',

    // postgres_with_primaries tags implies the service has primaries.
    // this is not the case for -archive and -delayed instances.
    'postgres_with_primaries',
  ],

  tenants: ['gitlab-ops'],

  monitoringThresholds: {
    apdexScore: 0.99,
    // Setting the Error SLO at 99% because we see high transaction rollback rates
    errorRatio: 0.99,
  },
  /*
   * Our anomaly detection uses normal distributions and the monitoring service
   * is prone to spikes that lead to a non-normal distribution. For that reason,
   * disable ops-rate anomaly detection on this service.
   */
  provisioning: {
    kubernetes: true,
    vms: false,
  },
  serviceLevelIndicators: {


    local sentryQuerySelector = { namespace: 'sentry' },

    sentry_events: {
      severity: 's3',
      userImpacting: false,
      featureCategory: 'not_owned',
      team: 'scalability:observability',
      description: |||
        Sentry is an application monitoring platform.
        This SLI monitors the sentry API. 5xx responses are considered failures.
      |||,

      apdex: histogramApdex(
        histogram='sentry_jobs_duration',
        selector=sentryQuerySelector,
        satisfiedThreshold=10,
      ),

      requestRate: rateMetric(
        counter='sentry_events_processed',
        selector={ job: 'sentry-metrics' },
      ),

      significantLabels: [],
    },

    sentry_nginx: {
      severity: 's3',
      userImpacting: false,
      featureCategory: 'not_owned',
      team: 'scalability:observability',
      description: |||
        Sentry is an application monitoring platform.
        This SLI monitors the sentry API. 5xx responses are considered failures.
      |||,

      apdex: histogramApdex(
        histogram='nginx_ingress_controller_request_duration_seconds_bucket',
        selector=sentryQuerySelector,
        satisfiedThreshold=10,
      ),

      requestRate: rateMetric(
        counter='nginx_ingress_controller_requests',
        selector=sentryQuerySelector,
      ),

      errorRate: rateMetric(
        counter='nginx_ingress_controller_requests',
        selector=sentryQuerySelector { status: { re: '^5.*' } },
      ),

      significantLabels: [],
    },

    postgresql_transactions: {
      severity: 's3',
      userImpacting: false,
      serviceAggregation: false,
      featureCategory: 'not_owned',
      description: |||
        Represents all SQL transactions issued to the sentry Postgres instance.
        Errors represent transaction rollbacks.
      |||,

      local postgresqlSelector = { database_id: 'gitlab-ops:sentry-63' },

      requestRate: rateMetric(
        counter='stackdriver_cloudsql_database_cloudsql_googleapis_com_database_postgresql_transaction_count',
        selector=postgresqlSelector,
      ),

      errorRate: rateMetric(
        counter='stackdriver_cloudsql_database_cloudsql_googleapis_com_database_postgresql_transaction_count',
        selector=postgresqlSelector { transaction_type: 'rollback' },
      ),

      emittedBy: ['monitoring'],

      significantLabels: [],
      toolingLinks: [
        toolingLinks.stackdriverLogs(
          title='Stackdriver Logs: Sentry',
          project='gitlab-ops',
          queryHash={
            'resource.type': 'cloudsql_database',
            'resource.labels.database_id': { contains: 'sentry' },
          },
        ),
      ],
    },

    memcached_commands: {
      severity: 's3',
      userImpacting: false,
      serviceAggregation: false,
      featureCategory: 'not_owned',
      description: |||
        Represents all commands the Sentry Memcached pods processed with a hit status.
        Errors represent all commands the Sentry Memcached pods failed to process with a badval status.
      |||,

      local memcachedSelector = { job: 'sentry-memcached-metrics' },

      requestRate: rateMetric(
        counter='memcached_commands_total',
        selector=memcachedSelector,
      ),

      errorRate: rateMetric(
        counter='memcached_commands_total',
        selector=memcachedSelector { status: 'badval' },
      ),

      significantLabels: [],
    },

    kafka_topics: {
      severity: 's3',
      userImpacting: false,
      serviceAggregation: false,
      featureCategory: 'not_owned',
      description: |||
        Represents all messages the Sentry Kafka pods processed.
        Errors represent all failed requests the Sentry Kafka pods failed to process.
      |||,

      local kafkaSelector = { type: 'sentry' },

      requestRate: rateMetric(
        counter='kafka_server_brokertopicmetrics_total_totalproducerequestspersec_count',
        selector=kafkaSelector,
      ),

      errorRate: rateMetric(
        counter='kafka_server_brokertopicmetrics_total_failedproducerequestspersec_count',
        selector=kafkaSelector,
      ),

      significantLabels: [],
    },

    redis_primary_server: {
      apdexSkip: 'apdex for redis is measured clientside',
      userImpacting: false,
      featureCategory: 'not_owned',
      serviceAggregation: false,
      description: |||
        Operations on the Redis primary for sentry's instance
      |||,

      requestRate: rateMetric(
        counter='redis_commands_processed_total',
        selector=sentryQuerySelector,
        instanceFilter='redis_instance_info{role="master"}'
      ),

      significantLabels: ['instance'],

      toolingLinks: [],
    },

    redis_secondary_servers: {
      apdexSkip: 'apdex for redis is measured clientside',
      userImpacting: false,  // userImpacting for data redundancy reasons
      featureCategory: 'not_owned',
      description: |||
        Operations on the Redis secondaries for the sentry instance.
      |||,

      requestRate: rateMetric(
        counter='redis_commands_processed_total',
        selector=sentryQuerySelector + { role: { eq: 'slave' } },
      ),

      significantLabels: ['instance'],
      serviceAggregation: false,
    },

    rabbitmq_messages: {
      severity: 's3',
      userImpacting: false,
      serviceAggregation: false,
      featureCategory: 'not_owned',
      description: |||
        Represents all messages the Sentry RabbitMQ pods processed.
        Errors represent all the messages the Sentry RabbitMQ pods attempted to process but were unroutable.
      |||,

      local rabbitmqSelector = { job: 'sentry-rabbitmq' },

      requestRate: rateMetric(
        counter='rabbitmq_global_messages_acknowledged_total',
        selector=rabbitmqSelector,
      ),

      errorRate: rateMetric(
        counter='rabbitmq_global_messages_unroutable_returned_total',
        selector=rabbitmqSelector,
      ),

      significantLabels: [],
    },
  },
  skippedMaturityCriteria: {
    'Structured logs available in Kibana': 'We are migrating our self-managed Sentry instance to the hosted one. For more information: https://gitlab.com/gitlab-com/gl-infra/reliability/-/issues/13963. Besides, Sentry logs are also available in Stackdriver.',
    'Service exists in the dependency graph': 'Sentry is an independent internal observability tool',
  },
})
