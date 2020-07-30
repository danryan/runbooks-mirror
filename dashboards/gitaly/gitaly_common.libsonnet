local basic = import 'grafana/basic.libsonnet';
local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local promQuery = import 'grafana/prom_query.libsonnet';
local seriesOverrides = import 'grafana/series_overrides.libsonnet';
local graphPanel = grafana.graphPanel;
local saturationResources = import './saturation-resources.libsonnet';

local generalGraphPanel(title, description=null, linewidth=2, sort='increasing') =
  graphPanel.new(
    title,
    linewidth=linewidth,
    fill=0,
    datasource='$PROMETHEUS_DS',
    description=description,
    decimals=2,
    sort=sort,
    legend_show=true,
    legend_values=true,
    legend_min=true,
    legend_max=true,
    legend_current=true,
    legend_total=false,
    legend_avg=true,
    legend_alignAsTable=true,
    legend_hideEmpty=true,
  )
  .addSeriesOverride(seriesOverrides.goldenMetric('/ service/'))
  .addSeriesOverride(seriesOverrides.upper)
  .addSeriesOverride(seriesOverrides.lower)
  .addSeriesOverride(seriesOverrides.upperLegacy)
  .addSeriesOverride(seriesOverrides.lowerLegacy)
  .addSeriesOverride(seriesOverrides.lastWeek)
  .addSeriesOverride(seriesOverrides.alertFiring)
  .addSeriesOverride(seriesOverrides.alertPending)
  .addSeriesOverride(seriesOverrides.degradationSlo)
  .addSeriesOverride(seriesOverrides.outageSlo)
  .addSeriesOverride(seriesOverrides.slo);

local ratelimitLockPercentage(selector) =
  generalGraphPanel(
    'Request % acquiring rate-limit lock within 1m, by host + method',
    description='Percentage of requests that acquire a Gitaly rate-limit lock within 1 minute, by host and method'
  )
  .addTarget(
    promQuery.target(
      |||
        sum(
          rate(
            gitaly_rate_limiting_acquiring_seconds_bucket{
              %(selector)s,
              le="60"
            }[$__interval]
          )
        ) by (environment, tier, type, stage, fqdn, grpc_method)
        /
        sum(
          rate(
            gitaly_rate_limiting_acquiring_seconds_bucket{
              %(selector)s,
              le="+Inf"
            }[$__interval]
          )
        ) by (environment, tier, type, stage, fqdn, grpc_method)
      ||| % { selector: selector },
      interval='30s',
      legendFormat='{{fqdn}} - {{grpc_method}}'
    )
  )
  .resetYaxes()
  .addYaxis(
    format='percentunit',
    min=0,
    max=1,
    label='%'
  )
  .addYaxis(
    format='short',
    show=false,
  );

// This needs to be kept manually in sync with the Gitaly apdex rule, in `service_apdex.yml`
local perNodeApdex(selector) =
  basic.apdexTimeseries(
    title='Apdex score per Gitaly Node',
    description='Apdex is a measure of requests that complete within an acceptable threshold duration. Actual threshold vary per service or endpoint. Higher is better.',
    query=|||
      (
        sum(rate(grpc_server_handling_seconds_bucket{%(selector)s, grpc_type="unary", le="0.5", grpc_method!~"GarbageCollect|Fsck|RepackFull|RepackIncremental|CommitLanguages|CreateRepositoryFromURL|UserFFBranch|UserRebase|UserSquash|CreateFork|UserUpdateBranch|FindRemoteRepository|UserCherryPick|FetchRemote|UserRevert|FindRemoteRootRef"}[1m])) by (environment, type, tier, stage, fqdn)
        +
        sum(rate(grpc_server_handling_seconds_bucket{%(selector)s, grpc_type="unary", le="1", grpc_method!~"GarbageCollect|Fsck|RepackFull|RepackIncremental|CommitLanguages|CreateRepositoryFromURL|UserFFBranch|UserRebase|UserSquash|CreateFork|UserUpdateBranch|FindRemoteRepository|UserCherryPick|FetchRemote|UserRevert|FindRemoteRootRef"}[1m])) by (environment, type, tier, stage, fqdn)
      )
      /
      2 / (sum(rate(grpc_server_handling_seconds_count{%(selector)s, grpc_type="unary", grpc_method!~"GarbageCollect|Fsck|RepackFull|RepackIncremental|CommitLanguages|CreateRepositoryFromURL|UserFFBranch|UserRebase|UserSquash|CreateFork|UserUpdateBranch|FindRemoteRepository|UserCherryPick|FetchRemote|UserRevert|FindRemoteRootRef"}[1m])) by (environment, type, tier, stage, fqdn))
    ||| % { selector: selector },
    legendFormat='{{ fqdn }}',
    interval='1m',
    linewidth=1,
    legend_show=false,
  );

local inflightGitalyCommandsPerNode(selector) =
  basic.timeseries(
    title='Inflight Git Commands per Server',
    description='Number of Git commands running concurrently per node. Lower is better.',
    query=|||
      avg_over_time(gitaly_commands_running{%(selector)s}[$__interval])
    ||| % { selector: selector },
    legendFormat='{{ fqdn }}',
    interval='1m',
    linewidth=1,
    legend_show=false,
  );

local gitalySpawnTimeoutsPerNode(selector) =
  basic.timeseries(
    title='Gitaly Spawn Timeouts per Node',
    description='Golang uses a global lock on process spawning. In order to control contention on this lock Gitaly uses a safety valve. If a request is unable to obtain the lock within a period, a timeout occurs. These timeouts are serious and should be addressed. Non-zero is bad.',
    query=|||
      increase(gitaly_spawn_timeouts_total{%(selector)s}[$__interval])
    ||| % { selector: selector },
    legendFormat='{{ fqdn }}',
    interval='1m',
    linewidth=1,
    legend_show=false,
  );

{
  ratelimitLockPercentage(selector):: ratelimitLockPercentage(selector),
  perNodeApdex(selector):: perNodeApdex(selector),
  inflightGitalyCommandsPerNode(selector):: inflightGitalyCommandsPerNode(selector),
  gitalySpawnTimeoutsPerNode(selector):: gitalySpawnTimeoutsPerNode(selector),
}
