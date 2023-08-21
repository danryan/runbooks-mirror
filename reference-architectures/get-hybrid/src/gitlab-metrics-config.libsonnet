local aggregationSets = import './reference-aggregation-sets.libsonnet';
local allServices = import './services/all.jsonnet';
local objects = import 'utils/objects.libsonnet';
local labelSet = (import 'label-taxonomy/label-set.libsonnet');
local validateReferenceArchitectureOptions = (import 'reference-architecture-options/validate.libsonnet');
local misc = import 'utils/misc.libsonnet';

local options = validateReferenceArchitectureOptions(import 'gitlab-metrics-options.libsonnet');

// Site-wide configuration options
{
  options:: options,

  // In accordance with the initial target in
  // https://gitlab.com/groups/gitlab-com/gl-infra/gitlab-dedicated/-/epics/55
  slaTarget:: 0.995,

  // List of services with SLI/SLO monitoring
  monitoredServices:: allServices,

  // Hash of all saturation metric types that are monitored on gitlab.com
  saturationMonitoring:: objects.mergeAll([
    import 'saturation-monitoring/cpu.libsonnet',
    import 'saturation-monitoring/disk_inodes.libsonnet',
    import 'saturation-monitoring/disk_space.libsonnet',
    import 'saturation-monitoring/go_memory.libsonnet',
    import 'saturation-monitoring/kube_container_cpu.libsonnet',
    import 'saturation-monitoring/kube_container_memory.libsonnet',
    import 'saturation-monitoring/kube_container_rss.libsonnet',
    import 'saturation-monitoring/kube_pool_cpu.libsonnet',
    import 'saturation-monitoring/opensearch_cpu.libsonnet',
    import 'saturation-monitoring/opensearch_disk_space.libsonnet',
    import 'saturation-monitoring/memory.libsonnet',
    import 'saturation-monitoring/node_schedstat_waiting.libsonnet',
    import 'saturation-monitoring/single_node_cpu.libsonnet',
  ] +
  std.get(options, 'saturationMonitoring', [])
  ),

  // Hash of all utilization metric types that are monitored on gitlab.com
  utilizationMonitoring:: objects.mergeAll([
    // TODO: add utilization monitoring
  ]),

  // Hash of all aggregation sets
  aggregationSets:: aggregationSets,

  serviceCatalog:: {
    teams: [],
    services: [
      {
        name: service.type,
        friendly_name: service.type,
        tier: service.tier,
      }
      for service in allServices
    ],
  },

  keyServices:
    local keyServices = ['webservice', 'registry'];
    local allServiceTypes = std.map(function(service) service.type, allServices);
    assert misc.all(function(service) std.member(allServiceTypes, service), keyServices) : 'not all keyservices are in the service catalog';
    keyServices,

  stageGroupMapping:: {},

  // The base selector for the environment, as configured in Grafana dashboards
  grafanaEnvironmentSelector:: {},

  // Signifies that a stage is partitioned into canary, main stage etc
  useEnvironmentStages:: false,

  // This metrics setup does not use Thanos to create a global view
  usesThanos:: false,

  // Name of the default Prometheus datasource to use
  defaultPrometheusDatasource: 'default',

  labelTaxonomy:: labelSet.makeLabelSet({
    environmentThanos: null,  // No thanos
    environment: null,  // Only one environment
    tier: null,  // No tiers
    service: 'type',
    stage: null,  // No stages
    shard: null,  // No shards
    node: 'node',
    sliComponent: 'component',
  }),

  separateGlobalRecordingSelectors: {},
}
