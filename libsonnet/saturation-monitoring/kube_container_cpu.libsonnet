local metricsCatalog = import 'servicemetrics/metrics-catalog.libsonnet';
local resourceSaturationPoint = (import 'servicemetrics/resource_saturation_point.libsonnet').resourceSaturationPoint;

local commonMemory = {
  severity: 's4',
  horizontallyScalable: true,
  appliesTo: metricsCatalog.findKubeProvisionedServices(first='web'),
  resourceLabels: ['pod', 'container'],
};
{
  kube_container_cpu: resourceSaturationPoint(commonMemory {
    title: 'Kube Container CPU Utilization',
    description: |||
      Kubernetes containers are allocated a share of CPU. Configured using resource requests.

      This is the amount of CPU that a container should always have available,
      though it can briefly utilize more. However, if a lot of pods on the same
      host exceed their requested CPU the container could be throttled earlier.

      This monitors utilization/allocated requests over a 1 hour period, and takes
      the 99th quantile of that utilization percentage in that period.
      We want the worst case to be around 80%-90% utilization,
      meaning we've sized the container correctly. If utilization is much higher than that
      the container could already be throttled because the host is overused, if it
      is much lower, then we could be underutilizing a host.

      This saturation point is only used for capacity planning.
      Containers that have a quota specified are excluded here and can be monitored using
      the `kube_container_throttling` saturation component.
      The burst utilization of a CPU is monitored and alerted upon using the
      `kube_container_cpu_limit` saturation point.
    |||,
    grafana_dashboard_uid: 'sat_kube_container_cpu',
    burnRatePeriod: '1h',
    quantileAggregation: 0.99,
    capacityPlanning: { strategy: 'quantile99_1h' },
    alerting: { enabled: false },
    query: |||
      (
        sum by (%(aggregationLabels)s) (
          rate(container_cpu_usage_seconds_total:labeled{container!="", container!="POD", %(selector)s}[%(rangeInterval)s])
        )
        unless on(%(aggregationLabels)s) (
          container_spec_cpu_quota:labeled{container!="", container!="POD", %(selector)s}
        )
      )
      /
      sum by(%(aggregationLabels)s) (
        kube_pod_container_resource_requests:labeled{container!="", container!="POD", resource="cpu", %(selector)s}
      )
    |||,
    slos: {
      soft: 0.95,
      hard: 0.99,
    },
  }),

  kube_container_cpu_limit: resourceSaturationPoint(commonMemory {
    title: 'Kube Container CPU over-utilization',
    description: |||
      Kubernetes containers can have a limit configured on how much CPU they can consume in
      a burst. If we are at this limit, exceeding the allocated requested resources, we
      should consider revisting the container's HPA configuration.

      When a container is utilizing CPU resources up-to it's configured limit for
      extended periods of time, this could cause it and other running containers to be
      throttled.
    |||,
    grafana_dashboard_uid: 'sat_kube_container_cpu_limit',
    burnRatePeriod: '5m',
    capacityPlanning: { strategy: 'exclude' },
    query: |||
      sum by (%(aggregationLabels)s) (
        rate(container_cpu_usage_seconds_total:labeled{container!="", container!="POD", %(selector)s}[%(rangeInterval)s])
      )
      /
      sum by(%(aggregationLabels)s) (
        container_spec_cpu_quota:labeled{container!="", container!="POD", %(selector)s}
        /
        container_spec_cpu_period:labeled{container!="", container!="POD", %(selector)s}
      )
    |||,
    slos: {
      soft: 0.90,
      hard: 0.99,
      alertTriggerDuration: '15m',
    },
  }),
}
