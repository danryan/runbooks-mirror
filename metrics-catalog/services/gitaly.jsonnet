local metricsCatalog = import '../lib/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;
local customQuery = metricsCatalog.customQuery;

{
  type: 'gitaly',
  tier: 'stor',
  autogenerateRecordingRules: false,  // TODO: enable autogeneration of recording rules for this service
  slos: {
    apdexRatio: 0.995,
    errorRatio: 0.001,
  },
  components: {
    goserver: {
      apdex: histogramApdex(
        histogram='grpc_server_handling_seconds_bucket',
        selector='type="gitaly", grpc_type="unary", grpc_method!~"GarbageCollect|Fsck|RepackFull|RepackIncremental|CommitLanguages|CreateRepositoryFromURL|UserRebase|UserSquash|CreateFork|UserUpdateBranch|FindRemoteRepository|UserCherryPick|FetchRemote|UserRevert|FindRemoteRootRef"',
        satisfiedThreshold=0.5,
        toleratedThreshold=1
      ),

      requestRate: rateMetric(
        counter='grpc_server_handled_total',
        selector='type="gitaly"'
      ),

      errorRate: rateMetric(
        counter='grpc_server_handled_total',
        selector='type="gitaly", grpc_code!~"^(OK|NotFound|Unauthenticated|AlreadyExists|FailedPrecondition)$"'
      ),
    },

    gitalyruby: {
      requestRate: rateMetric(
        counter='grpc_client_handled_total',
        selector='job="gitaly", type="gitaly"'
      ),

      errorRate: rateMetric(
        counter='grpc_client_handled_total',
        selector='job="gitaly", type="gitaly", grpc_code!~"^(OK|NotFound|Unauthenticated|AlreadyExists|FailedPrecondition)$"'
      ),
    },
  },
}
