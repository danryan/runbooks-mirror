local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local gaugeMetric = metricsCatalog.gaugeMetric;
local rateMetric = metricsCatalog.rateMetric;
local errorCounterApdex = metricsCatalog.errorCounterApdex;
local toolingLinks = import 'toolinglinks/toolinglinks.libsonnet';
local googleLoadBalancerComponents = import './lib/google_load_balancer_components.libsonnet';
local maturityLevels = import 'service-maturity/levels.libsonnet';
local kubeLabelSelectors = metricsCatalog.kubeLabelSelectors;

metricsCatalog.serviceDefinition({
  type: 'monitoring',
  tier: 'inf',

  tags: ['cloud-sql', 'golang', 'grafana', 'prometheus'],

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
  serviceDependencies: {
    'cloud-sql': true,
  },
  kubeResources: {
    grafana: {
      kind: 'Deployment',
      containers: [
        'grafana',
      ],
    },
    'grafana-image-renderer': {
      kind: 'Deployment',
      containers: [
        'grafana-image-renderer',
      ],
    },
  },
  serviceLevelIndicators: {

    // Prometheus Alert Manager Sender operations
    prometheus_alert_sender: {
      userImpacting: true,
      featureCategory: 'not_owned',
      description: |||
        This SLI monitors all prometheus alert notifications that are generated by AlertManager.
        Alert delivery failure is considered a service-level failure.
      |||,

      // There are >=3 alertmanagers, Prometheus sends alerts to all 3,
      // we can tolerate some errors for pod rotation etc.
      monitoringThresholds+: {
        errorRatio: 0.995,
      },

      local prometheusAlertsSelector = {
        job: 'prometheus',
        type: 'monitoring',
      },

      requestRate: rateMetric(
        counter='prometheus_notifications_sent_total',
        selector=prometheusAlertsSelector
      ),

      errorRate: rateMetric(
        counter='prometheus_notifications_errors_total',
        selector=prometheusAlertsSelector
      ),

      significantLabels: ['fqdn', 'pod', 'alertmanager'],
    },


    // This component represents the Google Load Balancer in front
    // of the internal Grafana instance at dashboards.gitlab.net
    grafana_google_lb: googleLoadBalancerComponents.googleLoadBalancer(
      userImpacting=false,
      // LB automatically created by the k8s ingress
      loadBalancerName='k8s2-um-4zodnh0s-grafana-grafana-cfagrqyu',
      projectId='gitlab-ops',
      trafficCessationAlertConfig=false,
      extra={
        severity: 's3',
      },
    ),

    prometheus: {
      userImpacting: true,
      featureCategory: 'not_owned',
      description: |||
        This SLI monitors Prometheus instances via the HTTP interface.
        5xx responses are considered errors.
      |||,

      local prometheusSelector = {
        job: { re: 'prometheus.*', ne: 'prometheus-metamon' },
        type: 'monitoring',
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

      significantLabels: ['fqdn', 'pod', 'handler'],

      toolingLinks: [
        toolingLinks.kibana(title='Prometheus (gprd)', index='monitoring_gprd', tag='monitoring.prometheus'),
        toolingLinks.kibana(title='Prometheus (ops)', index='monitoring_ops', tag='monitoring.prometheus'),
      ],
    },

    local prometheusSelector = {
      type: 'monitoring',
      job: { nre: '^thanos.*' },
    },

    rule_evaluation: {
      userImpacting: false,
      severity: 's3',
      featureCategory: 'not_owned',
      description: |||
        This SLI monitors Prometheus recording rule evaluations. Recording rule evalution failures are considered to be
        service failures.

        Prometheus rule groups are evaluating recording rules in a group in sequence at an interval.
        If the recording of all rules in a groups exceeds the interval for the group, we could be
        missing data points in the group.

        If a group fails often, we should split it up or improve query performance.

        To see which rules are often not meeting their target. Look at the SLI-details. The `rule_group` label will contain
        information about the slow group.
      |||,

      requestRate: rateMetric(
        counter='prometheus_rule_evaluations_total',
        selector=prometheusSelector
      ),

      errorRate: rateMetric(
        counter='prometheus_rule_evaluation_failures_total',
        selector=prometheusSelector
      ),

      apdex: errorCounterApdex(
        'prometheus_rule_group_iterations_missed_total',
        'prometheus_rule_group_iterations_total',
        selector=prometheusSelector,
      ),

      significantLabels: ['fqdn', 'pod', 'rule_group'],
    },

    grafana: {
      userImpacting: false,
      featureCategory: 'not_owned',
      trafficCessationAlertConfig: false,

      monitoringThresholds+: {
        apdexScore: 0.92,
      },

      description: |||
        Grafana builds and displays dashboards querying Thanos, Elasticsearch and other datasources.
        This SLI monitors the Grafana HTTP interface.
      |||,

      local grafanaSelector = {
        job: 'grafana',
        type: 'monitoring',
        shard: 'default',
      },

      apdex: histogramApdex(
        histogram='grafana_http_request_duration_seconds_bucket',
        selector=grafanaSelector,
        satisfiedThreshold=5,
        metricsFormat='openmetrics'
      ),

      requestRate: rateMetric(
        counter='grafana_http_request_duration_seconds_bucket',
        selector=grafanaSelector { le: '+Inf' },
      ),

      errorRate: rateMetric(
        counter='grafana_http_request_duration_seconds_bucket',
        selector=grafanaSelector { le: '+Inf', code: { re: '^5.*' } }
      ),

      significantLabels: ['pod'],
    },

    grafana_datasources: {
      userImpacting: false,
      featureCategory: 'not_owned',
      trafficCessationAlertConfig: false,

      description: |||
        Grafana builds and displays dashboards querying Thanos, Elasticsearch and other datasources.
        This SLI monitors the requests from Grafana to its datasources.
      |||,

      local grafanaSelector = {
        job: 'grafana',
        type: 'monitoring',
        shard: 'default',
      },

      requestRate: rateMetric(
        counter='grafana_datasource_request_total',
        selector=grafanaSelector,
      ),

      errorRate: rateMetric(
        counter='grafana_datasource_request_total',
        selector=grafanaSelector { code: { re: '^5.*' } }
      ),

      significantLabels: ['pod', 'datasource'],
    },

    grafana_image_renderer: {
      userImpacting: false,
      featureCategory: 'not_owned',
      trafficCessationAlertConfig: false,

      monitoringThresholds+: {
        apdexScore: 0.92,
      },

      description: |||
        The Grafana Image Renderer exports Grafana dashboards or panels to PNG for external use.
        This SLI monitors the Grafana Image Renderer HTTP interface.
      |||,

      local grafanaSelector = {
        job: 'grafana-image-renderer',
        type: 'monitoring',
        shard: 'default',
      },

      apdex: histogramApdex(
        histogram='grafana_image_renderer_service_http_request_duration_seconds_bucket',
        selector=grafanaSelector,
        satisfiedThreshold=30,
      ),

      requestRate: rateMetric(
        counter='grafana_image_renderer_service_http_request_duration_seconds_bucket',
        selector=grafanaSelector { le: '+Inf' },
      ),

      errorRate: rateMetric(
        counter='grafana_image_renderer_service_http_request_duration_seconds_bucket',
        selector=grafanaSelector { le: '+Inf', status_code: { re: '^5.*' } }
      ),

      significantLabels: ['pod'],
    },
  },
})
