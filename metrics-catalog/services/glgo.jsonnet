local runwayArchetype = import 'service-archetypes/runway-archetype.libsonnet';
local metricsCatalog = import 'servicemetrics/metrics.libsonnet';

metricsCatalog.serviceDefinition(
  // Default Runway SLIs
  runwayArchetype(
    type='glgo',
    team='reliability_general',
    apdexScore=0.98,
    errorRatio=0.98,
    apdexSatisfiedThreshold="1024"
  )
)
