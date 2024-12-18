local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;
local redisArchetype = import 'service-archetypes/redis-rails-archetype.libsonnet';
local redisHelpers = import './lib/redis-helpers.libsonnet';
local findServicesWithTag = (import 'servicemetrics/metrics-catalog.libsonnet').findServicesWithTag;

metricsCatalog.serviceDefinition(
  redisArchetype(
    type='redis-cluster-database-lb',
    railsStorageSelector=redisHelpers.storageSelector('cluster_db_load_balancing'),  // TODO switch to db_load_balancing after application-side clean up
    descriptiveName='Redis DB load balancing in Redis Cluster',
    redisCluster=true
  )
  {
    tenants: ['gitlab-gprd', 'gitlab-gstg', 'gitlab-pre'],
    monitoringThresholds+: {
      apdexScore: 0.9999,
    },
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
  + redisHelpers.gitlabcomObservabilityToolingForRedis('redis-cluster-database-lb')
)
