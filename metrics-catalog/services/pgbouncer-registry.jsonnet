local pgbouncerHelpers = import './lib/pgbouncer-helpers.libsonnet';
local pgbouncerArchetype = import 'service-archetypes/pgbouncer-archetype.libsonnet';
local metricsCatalog = import 'servicemetrics/metrics.libsonnet';

metricsCatalog.serviceDefinition(
  pgbouncerArchetype(
    type='pgbouncer-registry',
  )
  {
    serviceDependencies: {
      'patroni-registry': true,
    },
    skippedMaturityCriteria: {
      'Developer guides exist in developer documentation': 'pgbouncer is an infrastructure component, developers do not interact with it',
    },
  }
  + pgbouncerHelpers.gitlabcomObservabilityToolingForPgbouncer('pgbouncer-registry')
)
