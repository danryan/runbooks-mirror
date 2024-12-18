local redisCommon = import 'gitlab-dashboards/redis_common_graphs.libsonnet';

redisCommon.redisDashboard('redis-cluster-database-lb', cluster=true, hitRatio=true)
.overviewTrailer()
