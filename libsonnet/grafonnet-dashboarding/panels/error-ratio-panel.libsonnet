local overrides = import 'grafonnet-dashboarding/grafana/overrides.libsonnet';
local promQuery = import 'grafonnet-dashboarding/grafana/prom_query.libsonnet';
local timeSeriesPanel = import 'grafonnet-dashboarding/grafana/timeseries-panel.libsonnet';

// These requires need to move into `grafonnet-dashboarding`.
local seriesOverrides = import 'grafana/series_overrides.libsonnet';
local sliPromQL = import 'key-metric-panels/sli_promql.libsonnet';

local defaultErrorRatioDescription = 'Error rates are a measure of unhandled service exceptions per second. Client errors are excluded when possible. Lower is better';

{
  new(
    title,
    sli=null,  // SLI can be null if this panel is not being used for an SLI
    aggregationSet,
    selectorHash,
    stableId,
    legendFormat=null,
    compact=false,
    includeLastWeek=true,
    expectMultipleSeries=false,
    description=defaultErrorRatioDescription,
    fixedThreshold=null,
    shardLevelSli
  )::
    local panel =
      timeSeriesPanel.new(
        title=title,
        description=description,
        sort=sort,
        legend_show=!compact,
        linewidth=linewidth,
        stableId=stableId,
      )
      + timeSeriesPanel.g.queryOptions.withTargetsMixin([
        promQuery.target(
          primaryQueryExpr,
          legendFormat=legendFormat,
        ),
        promQuery.target(
          sliPromQL.errorRate.serviceErrorRateDegradationSLOQuery(selectorHash, fixedThreshold, shardLevelSli),
          interval='5m',
          legendFormat='6h Degradation SLO (5% of monthly error budget)' + (if shardLevelSli then ' - {{ shard }} shard' else ''),
        ),
        promQuery.target(
          sliPromQL.errorRate.serviceErrorRateOutageSLOQuery(selectorHash, fixedThreshold, shardLevelSli),
          interval='5m',
          legendFormat='1h Outage SLO (2% of monthly error budget)' + (if shardLevelSli then ' - {{ shard }} shard' else ''),
        ),
      ])
      + timeSeries.ratioOptions;

    panel,
}
