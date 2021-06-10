local aggregations = import 'promql/aggregations.libsonnet';
local strings = import 'utils/strings.libsonnet';

//
// EXPERIMENTAL: applying our application label taxonomy to cadvisor
// metrics would help use in attribution of problems.
// These recording rules, while bulky, allow us to apply the
// standard GitLab application labels (type, shard, stage) to
// the metrics we export via cadvisor
//

// TODO: initial spike only contains a small subset of metrics
// to ensure that this approach will work
local cadvisorMetrics = [
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
];

local kubePodContainerMetrics = [
  'kube_pod_container_status_running',
  'kube_pod_container_resource_limits_cpu_cores',
  'kube_pod_container_resource_limits_memory_bytes',
  'kube_pod_container_resource_requests_cpu_cores',
  'kube_pod_container_resource_requests_memory_bytes',

  // Kube pod status metrics, useful for measuring pod lifecycles
  'kube_pod_container_status_last_terminated_reason',
  'kube_pod_container_status_ready',
  'kube_pod_container_status_restarts_total',
  'kube_pod_container_status_running',
  'kube_pod_container_status_terminated',
  'kube_pod_container_status_terminated_reason',
  'kube_pod_container_status_waiting',
  'kube_pod_container_status_waiting_reason',
];

local kubeHPAMetrics = [
  'kube_hpa_spec_target_metric',
  'kube_hpa_status_condition',
  'kube_hpa_status_current_replicas',
  'kube_hpa_status_desired_replicas',
  'kube_hpa_metadata_generation',
  'kube_hpa_spec_max_replicas',
  'kube_hpa_spec_min_replicas',
];

local kubeNodeMetrics = [
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
];

local ingressMetrics = [
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
];

local podLabelJoinExpression(expression) =
  |||
    %(expression)s
    *
    on(pod) group_left(tier, type, stage, shard, deployment)
    topk by (pod) (1, kube_pod_labels:labeled{type!=""})
  ||| % {
    expression: expression,
  };

local kubeHPALabelJoinExpression(expression) =
  |||
    %(expression)s
    *
    on(hpa) group_left(tier, type, stage, shard)
    topk by (hpa) (1, kube_hpa_labels:labeled{type!=""})
  ||| % {
    expression: expression,
  };

// We filter to include only metrics_path="/metrics/cadvisor" series
// and exclude metrics_path="/metrics/resource/v1alpha1" etc
local cadvisorWithLabelNamesExpression(metricName) =
  podLabelJoinExpression('%(metricName)s{metrics_path="/metrics/cadvisor"}' % {
    metricName: metricName,
  });

local nodeLabelJoinExpression(expression) =
  |||
    %(expression)s
    *
    on(node) group_left(shard, stage, type, tier)
    topk by (node) (1, kube_node_labels:labeled)
  ||| % {
    expression: expression,
  };

local nginxIngressJoinExpression(expression) =
  |||
    %(expression)s
    *
    on(ingress) group_left(shard, stage, type, tier)
    topk by (ingress) (1, kube_ingress_labels:labeled)
  ||| % {
    expression: expression,
  };

local recordingRuleFor(metricName, expression) =
  {
    record: metricName + ':labeled',
    expr: expression,
  };

local relabel(expression, labelMap) =
  local fromLabels = std.objectFields(labelMap);
  local relabels = std.foldl(
    function(memo, labelFrom)
      local labelTo = labelMap[labelFrom];
      |||
        label_replace(
          %(memo)s,
          "%(labelTo)s", "$0", "%(labelFrom)s", ".*"
        )
      ||| % {
        labelTo: labelTo,
        labelFrom: labelFrom,
        memo: strings.indent(memo, 2),
      },
    fromLabels,
    expression
  );
  |||
    group without(%(fromLabels)s) (
      %(relabels)s
    )
  ||| % {
    fromLabels: aggregations.serialize(fromLabels),
    relabels: strings.indent(relabels, 2),
  };

local rules = {
  groups: [{
    name: 'kube-state-metrics-recording-rules',
    interval: '1m',
    rules: [
      // Relabel: kube_pod_labels
      recordingRuleFor(
        'kube_pod_labels',
        relabel(
          'topk by (pod) (1, kube_pod_labels{})',
          {
            label_tier: 'tier',
            label_type: 'type',
            label_stage: 'stage',
            label_queue_pod_name: 'shard',
            label_deployment: 'deployment',
          }
        )
      ),
    ] + [
      /* container_* recording rules */
      recordingRuleFor(metricName, cadvisorWithLabelNamesExpression(metricName))
      for metricName in cadvisorMetrics
    ] + [
      /* kube_pod_container_* recording rules */
      recordingRuleFor(metricName, podLabelJoinExpression(metricName))
      for metricName in kubePodContainerMetrics
    ] + [
      // Relabel: kube_hpa_labels
      recordingRuleFor(
        'kube_hpa_labels',
        relabel(
          'topk by (hpa) (1, kube_hpa_labels{})',
          {
            label_tier: 'tier',
            label_type: 'type',
            label_stage: 'stage',
            label_shard: 'shard',
          }
        )
      ),
    ] + [
      /* kube_hpa_* recording rules */
      recordingRuleFor(metricName, kubeHPALabelJoinExpression(metricName))
      for metricName in kubeHPAMetrics
    ] + [
      // Relabel: kube_node_labels
      recordingRuleFor(
        'kube_node_labels',
        relabel(
          |||
            kube_node_labels
            * on(label_type) group_left(service_type, service_tier, service_shard, service_stage)
            topk by(label_type) (1, gitlab:kube_node_pool_labels)
          |||,
          {
            service_tier: 'tier',
            service_type: 'type',
            service_stage: 'stage',
            service_shard: 'shard',
          }
        )
      ),
    ] + [
      /* node_* recording rules */
      recordingRuleFor(metricName, nodeLabelJoinExpression(metricName))
      for metricName in kubeNodeMetrics
    ] + [
      // Relabel: kube_ingress_labels
      recordingRuleFor(
        'kube_ingress_labels',
        relabel(
          |||
            topk by(label_type) (1, kube_ingress_labels)
          |||,
          {
            label_tier: 'tier',
            label_type: 'type',
            label_stage: 'stage',  // Requires https://gitlab.com/gitlab-com/gl-infra/delivery/-/issues/1727 to work
            service_shard: 'shard',  // Requires https://gitlab.com/gitlab-com/gl-infra/delivery/-/issues/1727 to work
          }
        )
      ),
    ] + [
      /* ingress recording rules */
      recordingRuleFor(metricName, nginxIngressJoinExpression(metricName))
      for metricName in ingressMetrics
    ],
  }],
};

{
  'kube-state-metrics-recording-rules.yml': std.manifestYamlDoc(rules),
}
