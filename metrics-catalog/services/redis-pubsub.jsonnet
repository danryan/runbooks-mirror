local redisHelpers = import './lib/redis-helpers.libsonnet';
local redisArchetype = import 'service-archetypes/redis-rails-archetype.libsonnet';
local metricsCatalog = import 'servicemetrics/metrics.libsonnet';

metricsCatalog.serviceDefinition(
  redisArchetype(
    type='redis-pubsub',
    railsStorageSelector=redisHelpers.storageSelector({ oneOf: ['workhorse', 'action_cable'] }),
    descriptiveName='Redis that handles predominantly pub/sub operations',
  )
  {
    tenants: ['gitlab-gprd', 'gitlab-gstg', 'gitlab-pre'],
  }
  + redisHelpers.gitlabcomObservabilityToolingForRedis('redis-pubsub')
)
