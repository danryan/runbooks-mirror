local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local resourceSaturationPoint = metricsCatalog.resourceSaturationPoint;
local saturationHelpers = import 'helpers/saturation_helpers.libsonnet';

{
  memory: resourceSaturationPoint({
    title: 'Memory Utilization per Node',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: saturationHelpers.vmProvisionedServices(default='gitaly'),
    description: |||
      Memory utilization per device per node.
    |||,
    grafana_dashboard_uid: 'sat_memory',
    resourceLabels: ['fqdn'],
    // Filter out fqdn nodes as these could be CI runners
    query: |||
      instance:node_memory_utilization:ratio{fqdn!="", %(selector)s}
    |||,
    slos: {
      soft: 0.90,
      hard: 0.98,
    },
  }),
}
