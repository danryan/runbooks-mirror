// This file is autogenerated using scripts/generate-service-dashboards
// Please feel free to customize this file.
local redisCommon = import 'gitlab-dashboards/redis_common_graphs.libsonnet';

redisCommon.redisDashboard('redis-pubsub', cluster=false, hitRatio=false)
.overviewTrailer()
