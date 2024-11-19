local g = import 'grafonnet-dashboarding/grafana/g.libsonnet';
local layout = import 'grafonnet-dashboarding/grafana/layout.libsonnet';
local overrides = import 'grafonnet-dashboarding/grafana/overrides.libsonnet';
local promQuery = import 'grafonnet-dashboarding/grafana/prom_query.libsonnet';
local timeSeriesPanel = import 'grafonnet-dashboarding/grafana/timeseries-panel.libsonnet';

local aggregationSets = (import 'gitlab-metrics-config.libsonnet').aggregationSets;

// These requires need to move into `grafonnet-dashboarding`.
local seriesOverrides = import 'grafana/series_overrides.libsonnet';
local sliPromQL = import 'key-metric-panels/sli_promql.libsonnet';

local apdexPanel(
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
      ) =
  local panel =
    timeSeriesPanel.new(
      title=title,
      description=description,
      sort=sort,
      legend_show=!compact,
      linewidth=if expectMultipleSeries then 2 else 4,
      stableId=stableId,
    )
    + timeSeriesPanel.panel.queryOptions.withTargetsMixin([
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
    + timeSeriesPanel.panel.standardOptions.withOverridesMixin(
      overrides.forPanel(timeSeriesPanel.panel).fromOptions(seriesOverrides.outageSlo)
    )
    + timeSeriesPanel.panel.standardOptions.withOverridesMixin(
      overrides.forPanel(timeSeriesPanel.panel).fromOptions(seriesOverrides.degradationSlo)
    )
    + timeSeriesPanel.panel.standardOptions.withUnit('percentunit')
    + timeSeriesPanel.panel.standardOptions.withMax(1)
    + timeSeriesPanel.panel.standardOptions.withMin(0)
    + timeSeriesPanel.panel.standardOptions.withDecimals(1)
    + (if !compact then timeSeriesPanel.defaultFieldConfig.withAxisLabel('Apdex %') else {})
    + (
      if !expectMultipleSeries then
        timeSeriesPanel.panel.queryOptions.withTargetsMixin([
          promQuery.query(
            sliPromQL.apdexQuery(aggregationSet, null, selectorHash, '$__interval', worstCase=false),
            legendFormat=legendFormat + ' avg',
          ),
        ])
        + timeSeriesPanel.panel.standardOptions.withOverridesMixin(
          overrides.forPanel(timeSeriesPanel.panel).fromOptions(seriesOverrides.averageCaseSeries(legendFormat + ' avg', { fillBelowTo: legendFormat }))
        )
      else {}
    )
    + (
      if !expectMultipleSeries && includeLastWeek then
        timeSeriesPanel.panel.queryOptions.withTargetsMixin([
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
        + timeSeriesPanel.panel.standardOptions.withOverridesMixin(
          overrides.forPanel(timeSeriesPanel.panel).fromOptions(seriesOverrides.lastWeek)
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
      + timeSeriesPanel.panel.queryOptions.withTargetsMixin([
        promQuery.query(
          sliPromQL.apdexConfidenceQuery(confidenceIntervalLevel, aggregationSet, null, selectorHash, '$__interval', worstCase=false),
          legendFormat=confidenceSignalSeriesName,
        ),
      ])
      + timeSeriesPanel.panel.standardOptions.withOverridesMixin(
        overrides.forPanel(timeSeriesPanel.panel).fromOptions(  // If there is a confidence SLI, we use that as the golden signal
          seriesOverrides.goldenMetric(confidenceSignalSeriesName)
        )
      )
      + timeSeriesPanel.panel.standardOptions.withOverridesMixin(
        overrides.forPanel(timeSeriesPanel.panel).fromOptions({
          alias: legendFormat,
          color: '#082e69',
          lines: true,
        })
      )
    else
      // If there is no confidence SLI, we use the main (non-confidence) signal as the golden signal
      panel
      + timeSeriesPanel.panel.standardOptions.withOverridesMixin(
        overrides.forPanel(timeSeriesPanel.panel).fromOptions(seriesOverrides.goldenMetric(legendFormat))
      );

  panelWithConfidenceIndicator;

local apdexStatusDescriptionPanel() = {};

local metricsRow(
  serviceType,
  sli,  // The serviceLevelIndicator object for which this row is being create (CAN BE NULL for headline rows etc)
  aggregationSet,
  selectorHash,
  titlePrefix,
  stableIdPrefix,
  legendFormatPrefix,
  showApdex,
  apdexDescription=null,
  showErrorRatio,
  showOpsRate,
  includePredictions=false,
  expectMultipleSeries=false,
  compact=false,
  includeLastWeek=true,
  fixedThreshold=null,
  shardLevelSli=false,
      ) =
  local formatConfig = {
    titlePrefix: titlePrefix,
    legendFormatPrefix: legendFormatPrefix,
    stableIdPrefix: stableIdPrefix,
    aggregationId: aggregationSet.id,
    // grafanaURLPairs: selectorToGrafanaURLParams(selectorHash),
  };
  local typeSelector = if serviceType == null then {} else { type: serviceType };
  local selectorHashWithExtras = selectorHash + typeSelector;

  local apdexPanels = if showApdex then
    [
      apdexPanel(
        title='%(titlePrefix)s Apdex' % formatConfig,
        sli=sli,
        aggregationSet=aggregationSet,
        selectorHash=selectorHashWithExtras,
        stableId='%(stableIdPrefix)s-apdex' % formatConfig,
        legendFormat='%(legendFormatPrefix)s apdex' % formatConfig,
        description=apdexDescription,
        expectMultipleSeries=expectMultipleSeries,
        compact=compact,
        fixedThreshold=fixedThreshold,
        includeLastWeek=includeLastWeek,
        shardLevelSli=shardLevelSli
      ),
    ]
  else [];

  // local errorRatioPanels = if showErrorRatio then [
  //   [
  //     errorRatioPanel(),
  //   ]
  //   + if expectMultipleSeries then [] else [
  //     errorRatioStatusDescriptionPanel(),
  //   ],
  // ] else [];

  // local opsRatePanels = if showOpsRate then [
  //   [
  //     opsRatePanel(),
  //   ],
  // ] else [];


  apdexPanels  // + errorRatioPanels + opsRatePanels
;

function(
  serviceType,
  startRow,
  rowTitle='🌡️ Aggregated Service Level Indicators (𝙎𝙇𝙄𝙨)',
  selectorHash={},
  stableIdPrefix='',
  showApdex=true,
  showErrorRatio=true,
  showOpsRate=true,
  showSaturationCell=true,
  compact=false,
  rowHeight=7,
  showDashboardListPanel=false,
  aggregationSet=aggregationSets.serviceSLIs,
  staticTitlePrefix=null,
  legendFormatPrefix=null,
  includeLastWeek=true,
  fixedThreshold=null
)
  local formatConfig = { serviceType: serviceType, stableIdPrefix: stableIdPrefix };
  local titlePrefix = if staticTitlePrefix == null then '%(serviceType)s Service' % formatConfig else staticTitlePrefix;

  local columns = metricsRow(
    serviceType=serviceType,
    sli=null,  // No SLI for headline metrics
    aggregationSet=aggregationSet,
    selectorHash=selectorHash,
    titlePrefix=titlePrefix,
    stableIdPrefix='%(stableIdPrefix)sservice-%(serviceType)s' % formatConfig,
    legendFormatPrefix=if legendFormatPrefix == null then serviceType else legendFormatPrefix,
    showApdex=showApdex,
    apdexDescription=null,
    showErrorRatio=showErrorRatio,
    showOpsRate=showOpsRate,
    includePredictions=true,
    compact=compact,
    includeLastWeek=includeLastWeek,
    fixedThreshold=fixedThreshold
  );

  if rowTitle != null then
    layout.titleRowWithPanels(rowTitle, columns, false, 0)
  else
    layout.grid(columns, cols=columns.size)
