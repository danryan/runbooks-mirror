local g = import 'grafonnet-dashboarding/grafana/g.libsonnet';
local layout = import 'grafonnet-dashboarding/grafana/layout.libsonnet';

local apdexPanel = import 'grafonnet-dashboarding/panels/apdex-panel.libsonnet';
local errorRatioPanel = import 'grafonnet-dashboarding/panels/error-ratio-panel.libsonnet';

local aggregationSets = (import 'gitlab-metrics-config.libsonnet').aggregationSets;

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
  includeOpsPredictions=false,
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
  local selectorHashWithExtras = aggregationSet.selector + typeSelector + selectorHash;

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
        linewidth=if expectMultipleSeries then 1 else 2,
        compact=compact,
        fixedThreshold=fixedThreshold,
        includeLastWeek=includeLastWeek && !expectMultipleSeries,
        includeAvg=!expectMultipleSeries,
        shardLevelSli=shardLevelSli
      ),
    ]
  else [];

  local errorRatioPanels = if showErrorRatio then
    [
      errorRatioPanel(
        '%(titlePrefix)s Error Ratio' % formatConfig,
        sli=sli,
        aggregationSet=aggregationSet,
        selectorHash=selectorHashWithExtras,
        stableId='%(stableIdPrefix)s-error-rate' % formatConfig,
        legendFormat='%(legendFormatPrefix)s error ratio' % formatConfig,
        linewidth=if expectMultipleSeries then 1 else 2,
        compact=compact,
        fixedThreshold=fixedThreshold,
        includeLastWeek=includeLastWeek && !expectMultipleSeries,
        includeAvg=!expectMultipleSeries,
        shardLevelSli=shardLevelSli
      ),
    ]
  else [];

  // local opsRatePanels = if showOpsRate then [
  //   [
  //     opsRatePanel(),
  //   ],
  // ] else [];


  apdexPanels + errorRatioPanels  //+ opsRatePanels
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
    includeOpsPredictions=true,
    compact=compact,
    includeLastWeek=includeLastWeek,
    fixedThreshold=fixedThreshold
  );

  if rowTitle != null then
    layout.titleRowWithPanels(rowTitle, columns)
  else
    layout.grid(columns, cols=columns.size)
