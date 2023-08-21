local metricsCatalog = import 'servicemetrics/metrics-catalog.libsonnet';
local resourceSaturationPoint = (import 'servicemetrics/resource_saturation_point.libsonnet').resourceSaturationPoint;

// Default saturation monitoring for Runway services
{
  runway_container_cpu_utilization: resourceSaturationPoint({
    title: 'Runway Container CPU Utilization',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: metricsCatalog.findRunwayProvisionedServices(),
    description: |||
      Container CPU utilization of the Runway service distributed across all container instances.

      For scaling, refer to https://cloud.google.com/run/docs/configuring/services/cpu.
    |||,
    grafana_dashboard_uid: 'sat_runway_container_cpu',
    resourceLabels: ['service_name'],
    burnRatePeriod: '30m',
    staticLabels: {
      type: 'sv',
      tier: 'inf',
      stage: 'main',
    },
    query: |||
      sum by (%(aggregationLabels)s) (
        avg_over_time(stackdriver_cloud_run_revision_run_googleapis_com_container_cpu_utilizations_sum{job="runway-exporter",%(selector)s}[%(rangeInterval)s])
      )
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),
  runway_container_memory_utilization: resourceSaturationPoint({
    title: 'Runway Container Memory Utilization',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: metricsCatalog.findRunwayProvisionedServices(),
    description: |||
      Container memory utilization of the Runway service distributed across all container instances.

      For scaling, refer to https://cloud.google.com/run/docs/configuring/services/memory-limits.
    |||,
    grafana_dashboard_uid: 'sat_runway_container_memory',
    resourceLabels: ['service_name'],
    burnRatePeriod: '30m',
    staticLabels: {
      type: 'sv',
      tier: 'inf',
      stage: 'main',
    },
    query: |||
      sum by (%(aggregationLabels)s) (
        avg_over_time(stackdriver_cloud_run_revision_run_googleapis_com_container_memory_utilizations_sum{job="runway-exporter",%(selector)s}[%(rangeInterval)s])
      )
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),
  runway_container_instance_utilization: resourceSaturationPoint({
    title: 'Runway Container Instance Utilization',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: metricsCatalog.findRunwayProvisionedServices(),
    description: |||
      Container instance utilization of the Runway service.

      For scaling, refer to https://cloud.google.com/run/docs/configuring/max-instances.
    |||,
    grafana_dashboard_uid: 'sat_runway_container_instance',
    resourceLabels: ['service_name'],
    burnRatePeriod: '30m',
    staticLabels: {
      type: 'sv',
      tier: 'inf',
      stage: 'main',
    },
    queryFormatConfig: {
      maximumInstances: 100,
    },
    query: |||
      sum by (%(aggregationLabels)s) (
        stackdriver_cloud_run_revision_run_googleapis_com_container_instance_count{job="runway-exporter",state="active",%(selector)s}
      )
      /
      %(maximumInstances)g
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),
  runway_container_max_concurrent_requests: resourceSaturationPoint({
    title: 'Runway Max Concurrent Requests',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: metricsCatalog.findRunwayProvisionedServices(),
    description: |||
      Max number of concurrent requests being served by each container instance of the Runway service.

      For scaling, refer to https://cloud.google.com/run/docs/configuring/concurrency.
    |||,
    grafana_dashboard_uid: 'sat_runway_container_max_con_reqs',
    resourceLabels: ['service_name'],
    burnRatePeriod: '30m',
    staticLabels: {
      type: 'sv',
      tier: 'inf',
      stage: 'main',
    },
    query: |||
      sum by (%(aggregationLabels)s) (
        avg_over_time(stackdriver_cloud_run_revision_run_googleapis_com_container_max_request_concurrencies_sum{job="runway-exporter",%(selector)s}[%(rangeInterval)s])
      )
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),
}
