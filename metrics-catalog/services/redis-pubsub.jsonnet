local redisHelpers = import './lib/redis-helpers.libsonnet';
local redisArchetype = import 'service-archetypes/redis-rails-archetype.libsonnet';
local metricsCatalog = import 'servicemetrics/metrics.libsonnet';

metricsCatalog.serviceDefinition(
  redisArchetype(
    type='redis-pubsub',
    // via Gitlab::Redis::Workhorse and Gitlab::Redis::Pubsub (initially, to be replaced by ActionCable)
    railsStorageSelector=redisHelpers.storageSelector({ oneOf: ['workhorse', 'pubsub'] }),
    descriptiveName='Redis that handles predominantly pub/sub operations',
  )
  {
    // TODO: set severity to s2 after migration is completed
    serviceLevelIndicators+: {
      rails_redis_client+: {
        userImpacting: true,
        severity: 's4',
      },
      primary_server+: {
        userImpacting: true,
        severity: 's4',
      },
      secondary_servers+: {
        userImpacting: true,
        severity: 's4',
      },
    },
  }
  + redisHelpers.gitlabcomObservabilityToolingForRedis('redis-pubsub')
)
