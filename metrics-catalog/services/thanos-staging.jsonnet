local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local gaugeMetric = metricsCatalog.gaugeMetric;
local rateMetric = metricsCatalog.rateMetric;
local errorCounterApdex = metricsCatalog.errorCounterApdex;
local toolingLinks = import 'toolinglinks/toolinglinks.libsonnet';
local googleLoadBalancerComponents = import './lib/google_load_balancer_components.libsonnet';
local kubeLabelSelectors = metricsCatalog.kubeLabelSelectors;
local combined = metricsCatalog.combined;

// Thanos operates across all stages and all environments,
// so we use special labels to merge environments and stages...
local staticLabels = {
  environment: 'thanos-staging',
  env: 'thanos-staging',
  stage: 'main',
  // This will be included by Thanos Ruler, but having it here helps with the labels on absent values
  monitor: 'global',
};

local thanosServiceSelector = { namespace: 'thanos-staging' };

metricsCatalog.serviceDefinition({
  type: 'thanos-staging',
  tier: 'inf',

  tags: ['golang', 'thanos'],

  monitoringThresholds: {},
  /*
   * Our anomaly detection uses normal distributions and the monitoring service
   * is prone to spikes that lead to a non-normal distribution. For that reason,
   * disable ops-rate anomaly detection on this service.
   */
  disableOpsRatePrediction: true,

  // Thanos needs to self-monitor in Thanos
  // this should not be required for other services.
  dangerouslyThanosEvaluated: true,

  thanosType: 'thanos-staging',

  // No stages for Thanos
  serviceIsStageless: true,

  provisioning: {
    kubernetes: true,
    vms: true,
  },
  serviceDependencies: {
    monitoring: true,
  },
  kubeResources: {
    'thanos-query': {
      kind: 'Deployment',
      containers: [
        'thanos-query',
      ],
    },
    'thanos-query-frontend': {
      kind: 'Deployment',
      containers: [
        'thanos-query-frontend',
      ],
    },
    'thanos-store': {
      kind: 'StatefulSet',
      containers: [
        'thanos-store',
      ],
    },
    'memcached-thanos-qfe-query-range': {
      kind: 'StatefulSet',
      containers: [
        'memcached',
      ],
    },
    'memcached-thanos-qfe-labels': {
      kind: 'StatefulSet',
      containers: [
        'memcached',
      ],
    },
    'memcached-thanos-bucket-cache': {
      kind: 'StatefulSet',
      containers: [
        'memcached',
      ],
    },
    'memcached-thanos-index-cache': {
      kind: 'StatefulSet',
      containers: [
        'memcached',
      ],
    },
  },
  serviceLevelIndicators: {
    thanos_query: {
      staticLabels: staticLabels,
      severity: 's3',
      team: 'reliability_observability',
      monitoringThresholds: {
        apdexScore: 0.95,
        errorRatio: 0.95,
      },
      userImpacting: false,
      featureCategory: 'not_owned',
      description: |||
        Thanos query gathers the data needed to evaluate Prometheus queries from multiple underlying prometheus and thanos instances.
        This SLI monitors the Thanos query HTTP interface. 5xx responses are considered failures.
      |||,

      local thanosQuerySelector = thanosServiceSelector {
        job: 'thanos-query',
        type: 'thanos',
      },

      apdex: histogramApdex(
        histogram='http_request_duration_seconds_bucket',
        selector=thanosQuerySelector,
        satisfiedThreshold=30,
        metricsFormat='openmetrics'
      ),

      requestRate: rateMetric(
        counter='http_requests_total',
        selector=thanosQuerySelector
      ),

      errorRate: rateMetric(
        counter='http_requests_total',
        selector=thanosQuerySelector { code: { re: '^5.*' } }
      ),

      significantLabels: ['pod'],
    },

    thanos_query_frontend: {
      staticLabels: staticLabels,
      severity: 's3',
      team: 'reliability_observability',
      monitoringThresholds: {
        apdexScore: 0.95,
        errorRatio: 0.95,
      },
      userImpacting: false,
      featureCategory: 'not_owned',
      description: |||
        Thanos query gathers the data needed to evaluate Prometheus queries from multiple underlying prometheus and thanos instances.
        This SLI monitors the Thanos query HTTP interface. 5xx responses are considered failures.
      |||,

      local thanosQuerySelector = thanosServiceSelector {
        job: 'thanos-query-frontend',
        type: 'thanos',
      },

      apdex: histogramApdex(
        histogram='http_request_duration_seconds_bucket',
        selector=thanosQuerySelector,
        satisfiedThreshold=30,
        metricsFormat='openmetrics'
      ),

      requestRate: rateMetric(
        counter='http_requests_total',
        selector=thanosQuerySelector
      ),

      errorRate: rateMetric(
        counter='http_requests_total',
        selector=thanosQuerySelector { code: { re: '^5.*' } }
      ),

      significantLabels: ['pod'],

      toolingLinks: [
        toolingLinks.kibana(title='Thanos Query', index='monitoring_ops', matches={ 'kubernetes.container_name': 'thanos-query-frontend' }),
      ],
    },

    thanos_store: {
      staticLabels: staticLabels,
      severity: 's3',
      team: 'reliability_observability',
      monitoringThresholds: {
        apdexScore: 0.95,
        errorRatio: 0.95,
      },
      userImpacting: false,
      featureCategory: 'not_owned',
      description: |||
        Thanos store will respond to Thanos Query (and other) requests for historical data. This historical data is kept in
        GCS buckets. This SLI monitors the Thanos StoreAPI GRPC endpoint. GRPC error responses are considered to be service-level failures.
      |||,

      local thanosStoreSelector = thanosServiceSelector {
        job: { re: '(.+)-thanos-storegateway' },  // TODO: FIXME: https://gitlab.com/gitlab-com/gl-infra/reliability/-/issues/17377
        grpc_type: 'unary',
        type: 'thanos',
      },

      apdex: histogramApdex(
        histogram='grpc_server_handling_seconds_bucket',
        selector=thanosStoreSelector,
        satisfiedThreshold=1,
        toleratedThreshold=3,
        metricsFormat='openmetrics'
      ),

      requestRate: rateMetric(
        counter='grpc_server_handled_total',
        selector=thanosStoreSelector
      ),

      errorRate: rateMetric(
        counter='grpc_server_handled_total',
        selector=thanosStoreSelector { grpc_code: { ne: 'OK' } }
      ),

      significantLabels: ['pod', 'job'],

      toolingLinks: [
        toolingLinks.kibana(title='Thanos Store (gprd)', index='monitoring_gprd', tag='monitoring.systemd.thanos-store'),
        toolingLinks.kibana(title='Thanos Store (ops)', index='monitoring_ops', tag='monitoring.systemd.thanos-store'),
      ],
    },

    thanos_compactor: {
      staticLabels: staticLabels,
      severity: 's3',
      team: 'reliability_observability',
      userImpacting: false,
      featureCategory: 'not_owned',
      trafficCessationAlertConfig: false,

      description: |||
        Thanos compactor is responsible for compaction of Prometheus series data into blocks, which are stored in GCS buckets.
        It also handles downsampling. This SLI monitors compaction operations and compaction failures.
      |||,

      local thanosCompactorSelector = thanosServiceSelector {
        type: 'thanos',
        job: { re: '(.+)-compactor' },
      },

      requestRate: rateMetric(
        counter='thanos_compact_group_compactions_total',
        selector=thanosCompactorSelector
      ),

      errorRate: rateMetric(
        counter='thanos_compact_group_compactions_failures_total',
        selector=thanosCompactorSelector
      ),

      significantLabels: ['pod'],

      toolingLinks: [
        toolingLinks.kibana(title='Thanos Compact (gprd)', index='monitoring_gprd', tag='monitoring.systemd.thanos-compact'),
        toolingLinks.kibana(title='Thanos Compact (ops)', index='monitoring_ops', tag='monitoring.systemd.thanos-compact'),
      ],
    },

    thanos_rule_alert_sender: {
      staticLabels: staticLabels,
      severity: 's3',
      team: 'reliability_observability',
      userImpacting: true,
      featureCategory: 'not_owned',
      description: |||
        This SLI monitors alerts generated by Thanos Ruler.
        Alert delivery failure is considered a service-level failure.
      |||,

      local thanosRuleAlertsSelector = thanosServiceSelector {
        job: 'thanos-ruler',  // TODO: FIXME: https://gitlab.com/gitlab-com/gl-infra/reliability/-/issues/17377
      },

      requestRate: rateMetric(
        counter='thanos_alert_sender_alerts_sent_total',
        selector=thanosRuleAlertsSelector
      ),

      errorRate: rateMetric(
        counter='thanos_alert_sender_alerts_dropped_total',
        selector=thanosRuleAlertsSelector
      ),

      significantLabels: ['pod'],

      toolingLinks: [
        toolingLinks.kibana(title='Thanos Rule', index='monitoring_ops', tag='monitoring.systemd.thanos-rule'),
      ],
    },

    // This component represents rule evaluations in
    // Prometheus and thanos ruler
    local rulerSelector = thanosServiceSelector {
      job: { re: 'thanos-thanos-stack-ruler(.*)' },
    },
    rule_evaluation: {
      staticLabels: staticLabels,
      severity: 's3',
      team: 'reliability_observability',
      userImpacting: false,
      featureCategory: 'not_owned',
      description: |||
        This SLI monitors Prometheus recording rule evaluations. Recording rule evalution failures are considered to be
        service failures. Warnings are also considered failures.

        Rule groups are evaluating recording rules in a group in sequence at an interval.
        If the recording of all rules in a groups exceeds the interval for the group, we could be
        missing data points in the group.

        If a group is slow often, we should split it up or improve query performance

        To see which rules are often not meeting their target. Look at the SLI-details. The `rule_group` label will contain
        information about the slow group.
      |||,

      requestRate: rateMetric(
        counter='prometheus_rule_evaluations_total',
        selector=rulerSelector
      ),

      // Importantly for thanos, we include Thanos Warnings as errors
      // These warnings are only warnings in that we prefer partial
      // evaluation as a recovery over complete failure.
      // We should still treat these warnings as a serious condition
      errorRate: combined([
        rateMetric(
          counter='prometheus_rule_evaluation_failures_total',
          selector=rulerSelector
        ),
        rateMetric(
          counter='thanos_rule_evaluation_with_warnings_total',
          selector=rulerSelector
        ),
      ]),

      apdex: errorCounterApdex(
        'prometheus_rule_group_iterations_missed_total',
        'prometheus_rule_group_iterations_total',
        selector=rulerSelector,
      ),

      significantLabels: ['pod', 'rule_group'],
    },

    thanos_memcached: {
      staticLabels: staticLabels,
      severity: 's3',
      team: 'reliability_observability',
      userImpacting: false,
      serviceAggregation: false,
      featureCategory: 'not_owned',
      trafficCessationAlertConfig: false,

      monitoringThresholds: {
        apdexScore: 0.999,
        errorRatio: 0.95,
      },

      description: |||
        Various memcached instances support our thanos infrastructure, for the
        store and query-frontend components.
      |||,

      local thanosMemcachedSelector = thanosServiceSelector {
        job: { re: 'thanos-(labels|querier)-metrics|thanos-(.+)-(bucket|index)-metrics' },
        grpc_type: 'unary',
      },


      apdex: histogramApdex(
        histogram='thanos_memcached_operation_duration_seconds_bucket',
        satisfiedThreshold=0.1,
        selector=thanosMemcachedSelector,
        metricsFormat='openmetrics'
      ),

      requestRate: rateMetric(
        counter='thanos_memcached_operations_total',
        selector=thanosMemcachedSelector,
      ),

      errorRate: rateMetric(
        counter='thanos_memcached_operation_failures_total',
        selector=thanosMemcachedSelector,
      ),

      significantLabels: ['operation', 'reason'],
    },
  },

  skippedMaturityCriteria: {
    'Service exists in the dependency graph': 'Thanos is an independent internal observability tool. It fetches metrics from other services, but does not interact with them, functionally',
  },
})
