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
  'container_cpu_cfs_periods_total',
  'container_cpu_cfs_throttled_periods_total',
  'container_cpu_usage_seconds_total',
  'container_memory_cache',
  'container_memory_swap',
  'container_memory_usage_bytes',
  'container_memory_working_set_bytes',
  'container_spec_cpu_period',
  'container_spec_cpu_quota',
  'container_spec_memory_limit_bytes',
];

// We filter to include only metrics_path="/metrics/cadvisor" series
// and exclude metrics_path="/metrics/resource/v1alpha1" etc
local cadvisorWithLabelNamesExpression(metricName) =
  |||
    min without(label_queue_pod_name, label_stage, label_type)
    (
      label_replace(
        label_replace(
          label_replace(
            %(metricName)s{metrics_path="/metrics/cadvisor"}
            *
            on(pod, cluster) group_left(label_type, label_stage, label_queue_pod_name)
            topk by (pod, cluster, label_type, label_stage, label_queue_pod_name) (1, kube_pod_labels{
              label_type!=""
            }),
            "shard", "$1", "label_queue_pod_name", "(.*)"
          ),
          "stage", "$1", "label_stage", "(.*)"
        ),
        "type", "$1", "label_type", "(.*)"
      )
    )
  ||| % {
    metricName: metricName,
  };

local recordingRuleFor(metricName) =
  {
    record: metricName + ':labeled',
    expr: cadvisorWithLabelNamesExpression(metricName),
  };

local rules = {
  groups: [{
    name: 'kube-cadvisor-recording-rules',
    interval: '1m',
    rules: [
      recordingRuleFor(metricName)
      for metricName in cadvisorMetrics
    ],
  }],
};

{
  'cadvisor-recording-rules.yml': std.manifestYamlDoc(rules),
}
