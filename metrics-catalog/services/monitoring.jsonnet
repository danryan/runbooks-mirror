local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;
local toolingLinks = import 'toolinglinks/toolinglinks.libsonnet';
local googleLoadBalancerComponents = import './lib/google_load_balancer_components.libsonnet';

local productionEnvironmentsSelector = {
  environment: { re: 'gprd|ops|ci-prd' },
};

metricsCatalog.serviceDefinition({
  type: 'monitoring',
  tier: 'inf',
  monitoringThresholds: {
    apdexScore: 0.999,
    errorRatio: 0.999,
  },
  /*
   * Our anomaly detection uses normal distributions and the monitoring service
   * is prone to spikes that lead to a non-normal distribution. For that reason,
   * disable ops-rate anomaly detection on this service.
   */
  disableOpsRatePrediction: true,
  provisioning: {
    kubernetes: true,
    vms: true,
  },
  kubeResources: {
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
      userImpacting: false,
      featureCategory: 'not_owned',
      team: 'sre_observability',
      description: |||
        Thanos query gathers the data needed to evaluate Prometheus queries from multiple underlying prometheus and thanos instances.
        This SLI monitors the Thanos query HTTP interface. 5xx responses are considered failures.
      |||,

      local thanosQuerySelector = productionEnvironmentsSelector {
        // The job regex was written while we were transitioning from a thanos
        // stack deployed in GCE to a new one deployed in GKE. job=thanos
        // covers all thanos components, but the metrics this filter is used for
        // are unambiguous because only the query component exposes them - in
        // the old stack.
        // In the new stack, we include the query frontend component, which we'd
        // prefer to measure from.
        // The generated rules always retain the "stage" label, which is used to
        // distinguish between the 2 stacks, so the metrics are never blended:
        // each job name is only present in one stack.
        job: { re: 'thanos|thanos-query-frontend' },
        type: 'monitoring',
        shard: 'default',
      },
      staticLabels: {
        environment: 'ops',
      },

      apdex: histogramApdex(
        histogram='http_request_duration_seconds_bucket',
        selector=thanosQuerySelector,
        satisfiedThreshold=30,
      ),

      requestRate: rateMetric(
        counter='http_requests_total',
        selector=thanosQuerySelector
      ),

      errorRate: rateMetric(
        counter='http_requests_total',
        selector=thanosQuerySelector { code: { re: '^5.*' } }
      ),

      significantLabels: ['fqdn'],

      toolingLinks: [
        toolingLinks.elasticAPM(service='thanos'),
        toolingLinks.kibana(title='Thanos Query', index='monitoring_ops', tag='monitoring.systemd.thanos-query'),
      ],
    },

    public_dashboards_thanos_query: {
      userImpacting: false,
      featureCategory: 'not_owned',
      team: 'sre_observability',
      ignoreTrafficCessation: true,

      description: |||
        Thanos query gathers the data needed to evaluate Prometheus queries from multiple underlying prometheus and thanos instances.
        This SLI monitors the Thanos query HTTP interface for GitLab's public Thanos instance, which is used by the public Grafana
        instance. 5xx responses are considered failures.
      |||,

      local thanosQuerySelector = productionEnvironmentsSelector {
        job: 'thanos',
        type: 'monitoring',
        shard: 'public-dashboards',
      },
      staticLabels: {
        environment: 'ops',
      },

      apdex: histogramApdex(
        histogram='http_request_duration_seconds_bucket',
        selector=thanosQuerySelector,
        satisfiedThreshold=30
      ),

      requestRate: rateMetric(
        counter='http_requests_total',
        selector=thanosQuerySelector
      ),

      errorRate: rateMetric(
        counter='http_requests_total',
        selector=thanosQuerySelector { code: { re: '^5.*' } }
      ),

      significantLabels: ['fqdn'],

      toolingLinks: [
        toolingLinks.elasticAPM(service='thanos'),
        toolingLinks.kibana(title='Thanos Query', index='monitoring_ops', tag='monitoring.systemd.thanos-query'),
      ],
    },

    thanos_store: {
      userImpacting: false,
      featureCategory: 'not_owned',
      team: 'sre_observability',
      description: |||
        Thanos store will respond to Thanos Query (and other) requests for historical data. This historical data is kept in
        GCS buckets. This SLI monitors the Thanos StoreAPI GRPC endpoint. GRPC error responses are considered to be service-level failures.
      |||,

      local thanosStoreSelector = productionEnvironmentsSelector {
        // Similar to the query selector above, we must pull data from jobs
        // corresponding to the old and new thanos stacks, which are mutually
        // exclusive by stage.
        job: { re: 'thanos|thanos-store-[0-9]+' },
        type: 'monitoring',
        grpc_service: 'thanos.Store',
        grpc_type: 'unary',
      },

      staticLabels: {
        environment: 'ops',
      },

      apdex: histogramApdex(
        histogram='grpc_server_handling_seconds_bucket',
        selector=thanosStoreSelector,
        satisfiedThreshold=1,
        toleratedThreshold=3
      ),

      requestRate: rateMetric(
        counter='grpc_server_handled_total',
        selector=thanosStoreSelector
      ),

      errorRate: rateMetric(
        counter='grpc_server_handled_total',
        selector=thanosStoreSelector { grpc_code: { ne: 'OK' } }
      ),

      significantLabels: ['fqdn'],

      toolingLinks: [
        toolingLinks.elasticAPM(service='thanos'),
        toolingLinks.kibana(title='Thanos Store (gprd)', index='monitoring_gprd', tag='monitoring.systemd.thanos-store'),
        toolingLinks.kibana(title='Thanos Store (ops)', index='monitoring_ops', tag='monitoring.systemd.thanos-store'),
      ],
    },

    thanos_compactor: {
      userImpacting: false,
      featureCategory: 'not_owned',
      team: 'sre_observability',
      ignoreTrafficCessation: true,

      description: |||
        Thanos compactor is responsible for compaction of Prometheus series data into blocks, which are stored in GCS buckets.
        It also handles downsampling. This SLI monitors compaction operations and compaction failures.
      |||,

      local thanosCompactorSelector = productionEnvironmentsSelector {
        job: 'thanos',
        type: 'monitoring',
      },

      staticLabels: {
        environment: 'ops',
      },

      requestRate: rateMetric(
        counter='thanos_compact_group_compactions_total',
        selector=thanosCompactorSelector
      ),

      errorRate: rateMetric(
        counter='thanos_compact_group_compactions_failures_total',
        selector=thanosCompactorSelector
      ),

      significantLabels: ['fqdn'],

      toolingLinks: [
        toolingLinks.elasticAPM(service='thanos'),
        toolingLinks.kibana(title='Thanos Compact (gprd)', index='monitoring_gprd', tag='monitoring.systemd.thanos-compact'),
        toolingLinks.kibana(title='Thanos Compact (ops)', index='monitoring_ops', tag='monitoring.systemd.thanos-compact'),
      ],
    },

    // Prometheus Alert Manager Sender operations
    prometheus_alert_sender: {
      userImpacting: true,
      featureCategory: 'not_owned',
      team: 'sre_observability',
      description: |||
        This SLI monitors all prometheus alert notifications that are generated by AlertManager.
        Alert delivery failure is considered a service-level failure.
      |||,

      local prometheusAlertsSelector = productionEnvironmentsSelector {
        job: 'prometheus',
        type: 'monitoring',
      },

      staticLabels: {
        environment: 'ops',
      },

      requestRate: rateMetric(
        counter='prometheus_notifications_sent_total',
        selector=prometheusAlertsSelector
      ),

      errorRate: rateMetric(
        counter='prometheus_notifications_errors_total',
        selector=prometheusAlertsSelector
      ),

      significantLabels: ['fqdn', 'alertmanager'],
    },

    thanos_rule_alert_sender: {
      userImpacting: true,
      featureCategory: 'not_owned',
      team: 'sre_observability',
      description: |||
        This SLI monitors alerts generated by Thanos Ruler.
        Alert delivery failure is considered a service-level failure.
      |||,

      local thanosRuleAlertsSelector = productionEnvironmentsSelector {
        job: 'thanos',
        type: 'monitoring',
      },

      staticLabels: {
        environment: 'ops',
      },

      requestRate: rateMetric(
        counter='thanos_alert_sender_alerts_sent_total',
        selector=thanosRuleAlertsSelector
      ),

      errorRate: rateMetric(
        counter='thanos_alert_sender_errors_total',
        selector=thanosRuleAlertsSelector
      ),

      significantLabels: ['fqdn'],

      toolingLinks: [
        toolingLinks.elasticAPM(service='thanos'),
        toolingLinks.kibana(title='Thanos Rule', index='monitoring_ops', tag='monitoring.systemd.thanos-rule'),
      ],
    },

    grafana: {
      userImpacting: true,
      featureCategory: 'not_owned',
      team: 'sre_observability',
      description: |||
        This SLI monitors the internal Grafana instance, via the HTTP interface.
        5xx responses are considered errors.
      |||,

      local grafanaSelector = productionEnvironmentsSelector {
        job: 'grafana',
      },

      staticLabels: {
        environment: 'ops',
      },

      requestRate: rateMetric(
        counter='http_request_total',
        selector=grafanaSelector
      ),

      errorRate: rateMetric(
        counter='http_request_total',
        selector=grafanaSelector { statuscode: { re: '^5.*' } }
      ),

      significantLabels: ['fqdn'],

      toolingLinks: [
        toolingLinks.googleLoadBalancer(
          instanceId='ops-dashboards',
          project='gitlab-ops',
        ),
      ],
    },

    // This component represents the Google Load Balancer in front
    // of the public Grafana instance at dashboards.gitlab.com
    public_grafana_googlelb: googleLoadBalancerComponents.googleLoadBalancer(
      userImpacting=false,
      loadBalancerName='ops-dashboards-com',
      projectId='gitlab-ops',
    ),

    prometheus: {
      userImpacting: true,
      featureCategory: 'not_owned',
      team: 'sre_observability',
      description: |||
        This SLI monitors Prometheus instances via the HTTP interface.
        5xx responses are considered errors.
      |||,

      local prometheusSelector = productionEnvironmentsSelector {
        job: 'prometheus',
        type: 'monitoring',
      },

      staticLabels: {
        environment: 'ops',
      },

      apdex: histogramApdex(
        histogram='prometheus_http_request_duration_seconds_bucket',
        selector=prometheusSelector,
        satisfiedThreshold=1,
        toleratedThreshold=3
      ),

      requestRate: rateMetric(
        counter='prometheus_http_requests_total',
        selector=prometheusSelector
      ),

      errorRate: rateMetric(
        counter='prometheus_http_requests_total',
        selector=prometheusSelector { code: { re: '^5.*' } }
      ),

      significantLabels: ['fqdn', 'handler'],

      toolingLinks: [
        toolingLinks.kibana(title='Prometheus (gprd)', index='monitoring_gprd', tag='monitoring.prometheus'),
        toolingLinks.kibana(title='Prometheus (ops)', index='monitoring_ops', tag='monitoring.prometheus'),
      ],
    },

    // This component represents rule evaluations in
    // Prometheus and thanos ruler
    rule_evaluation: {
      userImpacting: true,
      featureCategory: 'not_owned',
      team: 'sre_observability',
      description: |||
        This SLI monitors Prometheus recording rule evaluations. Recording rule evalution failures are considered to be
        service failures.
      |||,

      local selector = productionEnvironmentsSelector { type: 'monitoring' },

      requestRate: rateMetric(
        counter='prometheus_rule_evaluations_total',
        selector=selector
      ),

      errorRate: rateMetric(
        counter='prometheus_rule_evaluation_failures_total',
        selector=selector
      ),

      significantLabels: ['fqdn'],
    },

    // Trickster is a prometheus caching layer that serves requests to our
    // public Grafana instance
    trickster: {
      userImpacting: false,
      featureCategory: 'not_owned',
      team: 'sre_observability',
      ignoreTrafficCessation: true,

      description: |||
        This SLI monitors the Trickster HTTP interface.
      |||,

      staticLabels: {
        environment: 'ops',
      },

      apdex: histogramApdex(
        histogram='trickster_frontend_requests_duration_seconds_bucket',
        satisfiedThreshold=5,
        toleratedThreshold=20
      ),

      requestRate: rateMetric(
        counter='trickster_frontend_requests_total'
      ),

      errorRate: rateMetric(
        counter='trickster_frontend_requests_total',
        selector={ http_status: { re: '5.*' } }
      ),

      significantLabels: ['fqdn'],
    },

    local thanosMemcachedSLI(job) = {
      local selector = {
        job: job,
        type: 'monitoring',
      },

      userImpacting: false,
      featureCategory: 'not_owned',
      team: 'sre_observability',
      ignoreTrafficCessation: true,

      description: |||
        Various memcached instances support our thanos infrastructure, for the
        store and query-frontend components.
      |||,

      apdex: histogramApdex(
        histogram='thanos_memcached_operation_duration_seconds_bucket',
        satisfiedThreshold=1,
        selector=selector,
      ),

      requestRate: rateMetric(
        counter='memcached_commands_total',
        selector=selector,
      ),

      errorRate: rateMetric(
        counter='thanos_memcached_operation_failures_total',
        selector=selector,
      ),

      significantLabels: ['fqdn'],
    },

    // We can add thanos-store memcached jobs here if we end up choosing to use
    // memcached for store.
    memcached_thanos_qfe_query_range: thanosMemcachedSLI('memcached-thanos-qfe-query-range-metrics'),
    // Note that this label cache will not be deployed and metrics will be empty
    // until this TODO is resolved:
    // https://gitlab.com/gitlab-com/gl-infra/k8s-workloads/tanka-deployments/blob/master/environments/thanos/ops/main.jsonnet#L49
    memcached_thanos_qfe_labels: thanosMemcachedSLI('memcached-thanos-qfe-labels-metrics'),
  },
})
