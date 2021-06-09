local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local resourceSaturationPoint = metricsCatalog.resourceSaturationPoint;
local saturationHelpers = import 'helpers/saturation_helpers.libsonnet';

{
  cpu: resourceSaturationPoint({
    title: 'Average Service CPU Utilization',
    severity: 's3',
    horizontallyScalable: true,
    appliesTo: saturationHelpers.vmProvisionedServices(default='gitaly'),
    description: |||
      This resource measures average CPU utilization across an all cores in a service fleet.
      If it is becoming saturated, it may indicate that the fleet needs
      horizontal or vertical scaling.
    |||,
    grafana_dashboard_uid: 'sat_cpu',
    resourceLabels: [],
    burnRatePeriod: '5m',
    query: |||
      1 - avg by (%(aggregationLabels)s) (
        rate(node_cpu_seconds_total{mode="idle", %(selector)s}[%(rangeInterval)s])
      )
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),
}
