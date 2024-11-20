local overrides = import 'grafonnet-dashboarding/grafana/overrides.libsonnet';
local promQuery = import 'grafonnet-dashboarding/grafana/prom_query.libsonnet';
local timeSeriesPanel = import 'grafonnet-dashboarding/grafana/timeseries-panel.libsonnet';

// These requires need to move into `grafonnet-dashboarding`.
local seriesOverrides = import 'grafana/series_overrides.libsonnet';
local sliPromQL = import 'key-metric-panels/sli_promql.libsonnet';

function(
  title,
  sli,  // SLI can be null if this panel is not being used for an SLI
  aggregationSet,
  selectorHash,
  description=null,
  stableId,
  legendFormat=null,
  compact=false,
  sort='increasing',
  includeLastWeek=true,
  expectMultipleSeries=false,
  fixedThreshold=null,
  shardLevelSli
)
  local panel =
    timeSeriesPanel.new(
      title=title,
      description=description,
      sort=sort,
      legend_show=!compact,
      linewidth=if expectMultipleSeries then 2 else 4,
      stableId=stableId,
    )
    + timeSeriesPanel.g.queryOptions.withTargetsMixin([
      promQuery.query(
        expr=sliPromQL.apdexQuery(aggregationSet, null, selectorHash, '$__interval', worstCase=true),
        legendFormat=legendFormat,
      ),
      promQuery.query(
        sliPromQL.apdex.serviceApdexDegradationSLOQuery(selectorHash, fixedThreshold, shardLevelSli),
        interval='5m',
        legendFormat='6h Degradation SLO (5% of monthly error budget)' + (if shardLevelSli then ' - {{ shard }} shard' else ''),
      ),
      promQuery.query(
        sliPromQL.apdex.serviceApdexOutageSLOQuery(selectorHash, fixedThreshold, shardLevelSli),
        interval='5m',
        legendFormat='1h Outage SLO (2% of monthly error budget)' + (if shardLevelSli then ' - {{ shard }} shard' else ''),
      ),
    ])
    + timeSeriesPanel.g.standardOptions.withOverridesMixin(
      overrides.forPanel(timeSeriesPanel.g).fromOptions(seriesOverrides.outageSlo)
    )
    + timeSeriesPanel.g.standardOptions.withOverridesMixin(
      overrides.forPanel(timeSeriesPanel.g).fromOptions(seriesOverrides.degradationSlo)
    )
    + timeSeriesPanel.g.standardOptions.withUnit('percentunit')
    + timeSeriesPanel.g.standardOptions.withMax(1)
    + timeSeriesPanel.g.standardOptions.withMin(0)
    + timeSeriesPanel.g.standardOptions.withDecimals(1)
    + (if !compact then timeSeriesPanel.defaultFieldConfig.withAxisLabel('Apdex %') else {})
    + (
      if !expectMultipleSeries then
        timeSeriesPanel.g.queryOptions.withTargetsMixin([
          promQuery.query(
            sliPromQL.apdexQuery(aggregationSet, null, selectorHash, '$__interval', worstCase=false),
            legendFormat=legendFormat + ' avg',
          ),
        ])
        + timeSeriesPanel.g.standardOptions.withOverridesMixin(
          overrides.forPanel(timeSeriesPanel.g).fromOptions(seriesOverrides.averageCaseSeries(legendFormat + ' avg', { fillBelowTo: legendFormat }))
        )
      else {}
    )
    + (
      if !expectMultipleSeries && includeLastWeek then
        timeSeriesPanel.g.queryOptions.withTargetsMixin([
          promQuery.query(
            sliPromQL.apdexQuery(
              aggregationSet,
              null,
              selectorHash,
              range=null,
              offset='1w',
              clampToExpression=sliPromQL.apdex.serviceApdexOutageSLOQuery(selectorHash, fixedThreshold)
            ),
            legendFormat='last week',
          ),
        ])
        + timeSeriesPanel.g.standardOptions.withOverridesMixin(
          overrides.forPanel(timeSeriesPanel.g).fromOptions(seriesOverrides.lastWeek)
        )
      else
        {}
    );

  local confidenceIntervalLevel =
    if !expectMultipleSeries && sli != null && sli.usesConfidenceLevelForSLIAlerts() then
      sli.getConfidenceLevel()
    else
      null;

  // Add a confidence interval SLI if its enabled for the SLI AND
  // We aggregation set supports confidence level recording rules
  // at 5m (which is what we display SLIs at)
  local confidenceSLI =
    if confidenceIntervalLevel != null then
      aggregationSet.getApdexRatioConfidenceIntervalMetricForBurnRate('5m')
    else
      null;

  local panelWithConfidenceIndicator =
    if confidenceSLI != null then
      local confidenceSignalSeriesName = 'Apdex SLI (upper %s confidence boundary)' % [confidenceIntervalLevel];
      panel
      + timeSeriesPanel.g.queryOptions.withTargetsMixin([
        promQuery.query(
          sliPromQL.apdexConfidenceQuery(confidenceIntervalLevel, aggregationSet, null, selectorHash, '$__interval', worstCase=false),
          legendFormat=confidenceSignalSeriesName,
        ),
      ])
      + timeSeriesPanel.g.standardOptions.withOverridesMixin(
        overrides.forPanel(timeSeriesPanel.g).fromOptions(  // If there is a confidence SLI, we use that as the golden signal
          seriesOverrides.goldenMetric(confidenceSignalSeriesName)
        )
      )
      + timeSeriesPanel.g.standardOptions.withOverridesMixin(
        overrides.forPanel(timeSeriesPanel.g).fromOptions({
          alias: legendFormat,
          color: '#082e69',
          lines: true,
        })
      )
    else
      // If there is no confidence SLI, we use the main (non-confidence) signal as the golden signal
      panel
      + timeSeriesPanel.g.standardOptions.withOverridesMixin(
        overrides.forPanel(timeSeriesPanel.g).fromOptions(seriesOverrides.goldenMetric(legendFormat))
      );

  panelWithConfidenceIndicator
