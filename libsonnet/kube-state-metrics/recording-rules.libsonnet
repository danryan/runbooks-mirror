local labelTaxonomy = import 'label-taxonomy/label-taxonomy.libsonnet';
local aggregations = import 'promql/aggregations.libsonnet';
local selectors = import 'promql/selectors.libsonnet';
local metricsCatalog = import 'servicemetrics/metrics-catalog.libsonnet';
local objects = import 'utils/objects.libsonnet';
local strings = import 'utils/strings.libsonnet';

// These are common labels used in join expressions for kube-state-metrics
local commonJoinOnLabels =
  labelTaxonomy.labelTaxonomy(labelTaxonomy.labels.environment) +
  ['cluster'];

local commonGroupLeftLabels = labelTaxonomy.labelTaxonomy(
  labelTaxonomy.labels.tier |
  labelTaxonomy.labels.service |
  labelTaxonomy.labels.stage |
  labelTaxonomy.labels.shard
);

local commonLabelSelector = { [labelTaxonomy.getLabelFor(labelTaxonomy.labels.service)]: { ne: '' } };

// kubeStateMetricTypeDescriptors describes each of the kubernetes resource that we monitor
// via kube-state-metrics. If you're looking to monitoring more kubernetes resources, add them to this
// list
local kubeStateMetricTypeDescriptors = {
  // Note: Container metrics is a special case since it relies on pod metrics
  // instead of it's own _label type
  container: {
    kubeLabelMetric: 'kube_pod_labels',
    keyLabel: 'pod',
    extraLabels: ['deployment'],
    metrics: [
      'container_start_time_seconds',
      'container_cpu_cfs_periods_total',
      'container_cpu_cfs_throttled_periods_total',
      'container_cpu_usage_seconds_total',
      'container_memory_cache',
      'container_memory_swap',
      'container_memory_usage_bytes',
      'container_memory_working_set_bytes',
      'container_network_receive_bytes_total',
      'container_network_transmit_bytes_total',
      'container_spec_cpu_period',
      'container_spec_cpu_quota',
      'container_spec_cpu_shares',
      'container_spec_memory_limit_bytes',
    ],

    // This filter will be applied to all metrics in the `metrics` list
    // We do this to reduce the number of metrics we need to query
    // Since these metrics are also generated by cadvisor on some VM services
    metricsFilter: { metrics_path: '/metrics/cadvisor' },
  },

  pod: {
    kubeLabelMetric: 'kube_pod_labels',
    keyLabel: 'pod',
    extraLabels: ['deployment'],
    metrics: [
      'kube_pod_container_status_running',
      'kube_pod_container_resource_limits',
      'kube_pod_container_resource_requests',

      // Kube pod status metrics, useful for measuring pod lifecycles
      'kube_pod_container_status_last_terminated_reason',
      'kube_pod_container_status_ready',
      'kube_pod_container_status_restarts_total',
      'kube_pod_container_status_running',
      'kube_pod_container_status_terminated',
      'kube_pod_container_status_terminated_reason',
      'kube_pod_container_status_waiting',
      'kube_pod_container_status_waiting_reason',
    ],
    metricsFilter: null,
  },

  hpa: {
    kubeLabelMetric: 'kube_horizontalpodautoscaler_labels',
    keyLabel: 'horizontalpodautoscaler',
    extraLabels: [],
    metrics: [
      'kube_horizontalpodautoscaler_spec_target_metric',
      'kube_horizontalpodautoscaler_status_condition',
      'kube_horizontalpodautoscaler_status_current_replicas',
      'kube_horizontalpodautoscaler_status_desired_replicas',
      'kube_horizontalpodautoscaler_metadata_generation',
      'kube_horizontalpodautoscaler_spec_max_replicas',
      'kube_horizontalpodautoscaler_spec_min_replicas',
    ],
    metricsFilter: null,
  },

  node: {
    kubeLabelMetric: 'kube_node_labels',
    keyLabel: 'node',
    extraLabels: [],
    metrics: [
      'kube_node_status_capacity',
      'kube_node_status_allocatable',
      'kube_node_status_condition',
      'node_schedstat_waiting_seconds_total',
      'node_cpu_seconds_total',
      'node_network_transmit_bytes_total',
      'node_network_receive_bytes_total',
      'node_disk_reads_completed_total',
      'node_disk_writes_completed_total',
      'node_disk_read_bytes_total',
      'node_disk_written_bytes_total',
      'node_disk_read_time_seconds_total',
      'node_disk_write_time_seconds_total',
      'node_load1',
      'node_load5',
      'node_load15',
      'node_vmstat_oom_kill',
    ],
    metricsFilter: null,  // TODO: consider a metrics filter on node_* to avoid VM metrics
  },

  ingress: {
    kubeLabelMetric: 'kube_ingress_labels',
    keyLabel: 'ingress',
    extraLabels: [],
    metrics: [
      'nginx_ingress_controller_bytes_sent_count',
      'nginx_ingress_controller_request_duration_seconds_bucket',
      'nginx_ingress_controller_request_duration_seconds_sum',
      'nginx_ingress_controller_response_size_count',
      'nginx_ingress_controller_ingress_upstream_latency_seconds',
      'nginx_ingress_controller_ingress_upstream_latency_seconds_count',
      'nginx_ingress_controller_ingress_upstream_latency_seconds_sum',
      'nginx_ingress_controller_request_duration_seconds_count',
      'nginx_ingress_controller_request_size_bucket',
      'nginx_ingress_controller_response_duration_seconds_bucket',
      'nginx_ingress_controller_bytes_sent_bucket',
      'nginx_ingress_controller_bytes_sent_sum',
      'nginx_ingress_controller_request_size_count',
      'nginx_ingress_controller_response_duration_seconds_sum',
      'nginx_ingress_controller_request_size_sum',
      'nginx_ingress_controller_requests',
      'nginx_ingress_controller_response_duration_seconds_count',
      'nginx_ingress_controller_response_size_bucket',
      'nginx_ingress_controller_response_size_sum',
    ],
    metricsFilter: null,
  },

  deployment: {
    kubeLabelMetric: 'kube_deployment_labels',
    keyLabel: 'deployment',
    extraLabels: [],
    metrics: [
      'kube_deployment_status_replicas_unavailable',
      'kube_deployment_status_replicas_updated',
      'kube_deployment_spec_paused',
      'kube_deployment_spec_replicas',
      'kube_deployment_spec_strategy_rollingupdate_max_surge',
      'kube_deployment_spec_strategy_rollingupdate_max_unavailable',
      'kube_deployment_status_condition',
      'kube_deployment_status_replicas_available',
      'kube_deployment_created',
      'kube_deployment_metadata_generation',
      'kube_deployment_status_observed_generation',
      'kube_deployment_status_replicas',
    ],
    metricsFilter: null,
  },
};

local groupLeftJoinExpression(descriptor) =
  local joinOnLabels = commonJoinOnLabels + [descriptor.keyLabel];
  local groupLeftLabels = commonGroupLeftLabels + descriptor.extraLabels;
  local joinedMetric = descriptor.kubeLabelMetric + ':labeled';
  local joinedMetricSelector = commonLabelSelector;

  |||
    on(%(joinOnLabels)s) group_left(%(groupLeftLabels)s)
    topk by (%(joinOnLabels)s) (1, %(joinedMetric)s{%(joinedMetricSelector)s})
  ||| % {
    joinOnLabels: aggregations.serialize(joinOnLabels),
    groupLeftLabels: aggregations.serialize(groupLeftLabels),
    joinedMetric: joinedMetric,
    joinedMetricSelector: selectors.serializeHash(joinedMetricSelector),
  };


local descriptorJoinedWithLabelsExpression(metricName, descriptor) =
  local metricsFilter = descriptor.metricsFilter;

  strings.chomp(|||
    %(metricName)s%(metricsFilter)s
    *
    %(groupLeftJoinExpression)s
  |||) % {
    metricName: metricName,
    metricsFilter: selectors.serializeHash(metricsFilter, withBraces=true),
    groupLeftJoinExpression: groupLeftJoinExpression(descriptor),
  };

local recordingRulesFor(metricName, labels, expression) =
  if expression == null then
    []
  else
    [{
      record: metricName + ':labeled',
      [if labels != {} then 'labels']: labels,
      expr: expression,
    }];

local kubernetesSelectorToKubeStatePromSelector(selector) =
  objects.mapKeyValues(
    function(key, value)
      // Certain labels don't need a prefix
      // TODO: Ask Charts team to add app label to hpa's
      if key == 'namespace' || key == 'horizontalpodautoscaler' then
        [key, value]
      else
        ['label_' + key, value],
    selector
  );

// Given the descriptor, the kubernetes label selector and any static labels that will
// be applied, generates a promql expression to migrate labels, ready for use in the
// recording rules.
local generateRelabelingExpression(descriptor, kubernetesLabelSelector, staticLabels) =
  local keyLabel = descriptor.keyLabel;
  local infoMetric = descriptor.kubeLabelMetric;

  // If a service doesn't have a selector for the given resource, that means that
  // if doesn't have any of those resources
  if kubernetesLabelSelector == null then
    null
  else
    local kubernetesSelectorExpression = kubernetesSelectorToKubeStatePromSelector(kubernetesLabelSelector);

    local topKAggregationLabels = commonJoinOnLabels + [keyLabel];

    local baseExpression = 'topk by(%(topKAggregationLabels)s) (1, %(infoMetric)s{%(kubernetesSelectorExpression)s})' % {
      kubernetesSelectorExpression: selectors.serializeHash(kubernetesSelectorExpression),
      keyLabel: keyLabel,
      infoMetric: infoMetric,
      topKAggregationLabels: aggregations.serialize(topKAggregationLabels),
    };

    local dynamicLabels = labelTaxonomy.labelTaxonomy(labelTaxonomy.labels.stage | labelTaxonomy.labels.shard) + descriptor.extraLabels;

    // Remove any static labels that may appear in the set of dynamic labels too
    local dynamicLabelsFiltered = std.filter(function(l) !std.objectHas(staticLabels, l), dynamicLabels);

    local relabels = std.foldl(
      function(memo, label)
        |||
          label_replace(
            %(memo)s,
            "%(label)s", "$0", "label_%(label)s", ".*"
          )
        ||| % {
          label: label,
          memo: strings.indent(memo, 2),
        },
      dynamicLabelsFiltered,
      baseExpression
    );

    if dynamicLabelsFiltered == [] then
      relabels
    else
      local labelsToRemove = std.map(function(l) 'label_' + l, dynamicLabelsFiltered);
      |||
        group without(%(labelsToRemove)s) (
          %(relabels)s
        )
      ||| % {
        labelsToRemove: aggregations.serialize(labelsToRemove),
        relabels: strings.indent(relabels, 2),
      };

local generateLabeledMetricsForServiceType(service, kubeMetricType) =
  local descriptor = kubeStateMetricTypeDescriptors[kubeMetricType];
  local kubernetesLabelSelector = service.kubeConfig.labelSelectors[kubeMetricType];
  local defaultStaticLabels = { type: service.type, tier: service.tier };
  local staticLabels = defaultStaticLabels + service.kubeConfig.labelSelectors.staticLabels[kubeMetricType];

  recordingRulesFor(
    descriptor.kubeLabelMetric,
    labels=staticLabels,
    expression=generateRelabelingExpression(descriptor, kubernetesLabelSelector, staticLabels)
  );

// For a given service, this function will generate recording rules to
// select the appropriate kubernetes resources that are owned by the service
local generateKubeSelectorRulesForService(service) =
  local formatConfig = { type: service.type };

  {
    name: 'kube-state-metrics-recording-rules: %(type)s' % formatConfig,
    interval: '1m',
    rules:
      generateLabeledMetricsForServiceType(service, 'pod') +
      generateLabeledMetricsForServiceType(service, 'hpa') +
      generateLabeledMetricsForServiceType(service, 'node') +
      generateLabeledMetricsForServiceType(service, 'ingress') +
      generateLabeledMetricsForServiceType(service, 'deployment'),
  };

// For a given kubernetes resource type, will generate recording rules tha enrich the labelling
// to make it easier to identify the resources for each service (as generated in `generateKubeSelectorRulesForService`)
local generateEnrichedLabelsForType(descriptorType) =
  local descriptor = kubeStateMetricTypeDescriptors[descriptorType];

  std.flatMap(
    function(metricName)
      recordingRulesFor(metricName, labels={}, expression=descriptorJoinedWithLabelsExpression(metricName, descriptor)),
    descriptor.metrics
  );

local kubeServices = std.filter(function(s) s.provisioning.kubernetes, metricsCatalog.services);

[
  generateKubeSelectorRulesForService(service)
  for service in kubeServices
] + [{
  name: 'kube-state-metrics-recording-rules: enriched label recording rules',
  interval: '1m',
  rules:
    generateEnrichedLabelsForType('container') +
    generateEnrichedLabelsForType('pod') +
    generateEnrichedLabelsForType('hpa') +
    generateEnrichedLabelsForType('node') +
    generateEnrichedLabelsForType('ingress') +
    generateEnrichedLabelsForType('deployment'),
}]
