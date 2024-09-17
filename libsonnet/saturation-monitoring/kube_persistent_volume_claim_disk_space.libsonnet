local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local resourceSaturationPoint = metricsCatalog.resourceSaturationPoint;

{
  kube_persistent_volume_claim_disk_space: resourceSaturationPoint({
    title: 'Kube Persistent Volume Claim Space Utilisation',
    severity: 's2',
    horizontallyScalable: true,
    appliesTo: ['kube'],
    description: |||
      disk space utilization on persistent volume claims.
    |||,
    runbook: 'docs/kube/kubernetes.md',
    grafana_dashboard_uid: 'sat_kube_pvc_disk_space',
    resourceLabels: ['cluster', 'namespace', 'persistentvolumeclaim'],
    useResourceLabelsAsMaxAggregationLabels: true,
    // TODO: keep these resources with the services they're managing, once https://gitlab.com/gitlab-com/gl-infra/reliability/-/issues/10249 is resolved
    // do not apply static labels
    staticLabels: {
      type: 'kube',
      tier: 'inf',
      stage: 'main',
    },
    query: |||
      kubelet_volume_stats_used_bytes
      /
      kubelet_volume_stats_capacity_bytes
    |||,
    slos: {
      soft: 0.85,
      hard: 0.90,
    },
    capacityPlanning: {
      saturation_dimension_dynamic_lookup_query: |||
        sum by(persistentvolumeclaim) (
          last_over_time(kubelet_volume_stats_used_bytes[1w])
        )
      |||,
    },
  }),
}
