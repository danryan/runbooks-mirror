local aggregationSets = (import 'gitlab-metrics-config.libsonnet').aggregationSets;
local timeSeriesPanel = import 'grafonnet-dashboarding/grafana/timeseries-panel.libsonnet';
local layout = import 'grafonnet-dashboarding/grafana/layout.libsonnet';
local promQuery = import 'grafonnet-dashboarding/grafana/prom_query.libsonnet';

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
  timeSeriesPanel(
    title=title,
    description=description,
    sort=sort,
    legend_show=!compact,
    linewidth=if expectMultipleSeries then 1 else 2,
    stableId=stableId,
  ).addTarget(
    promQuery.query(
      expr=sliPromQL.apdexQuery(aggregationSet, null, selectorHash, '$__interval', worstCase=true),
      legendFormat=legendFormat + ' avg',
    )
  );

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
