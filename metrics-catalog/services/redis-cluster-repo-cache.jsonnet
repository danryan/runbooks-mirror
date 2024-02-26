local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;
local redisArchetype = import 'service-archetypes/redis-rails-archetype.libsonnet';
local redisHelpers = import './lib/redis-helpers.libsonnet';
local findServicesWithTag = (import 'servicemetrics/metrics-catalog.libsonnet').findServicesWithTag;

local railsCacheSelector = redisHelpers.storeSelector('RedisRepositoryCache');

metricsCatalog.serviceDefinition(
  redisArchetype(
    type='redis-cluster-repo-cache',  // name is shortened due to CloudDNS 255 char limits
    railsStorageSelector=redisHelpers.storageSelector('cluster_repository_cache'),  // TODO switch to repository_cache after application-side clean up
    descriptiveName='Redis Repository Cache in Redis Cluster',
    redisCluster=true
  )
  {
    monitoringThresholds+: {
      apdexScore: 0.9995,
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
      rails_cache: {
        userImpacting: true,
        severity: 's4',
        featureCategory: 'not_owned',
        description: |||
          Rails ActiveSupport Cache operations against the Redis Cache
        |||,

        apdex: histogramApdex(
          histogram='gitlab_cache_operation_duration_seconds_bucket',
          selector=railsCacheSelector,
          satisfiedThreshold=0.01,
          toleratedThreshold=0.1
        ),

        requestRate: rateMetric(
          counter='gitlab_cache_operation_duration_seconds_count',
          selector=railsCacheSelector,
        ),

        emittedBy: findServicesWithTag(tag='rails'),

        significantLabels: [],
      },
    },
  }
  + redisHelpers.gitlabcomObservabilityToolingForRedis('redis-cluster-repo-cache')
)