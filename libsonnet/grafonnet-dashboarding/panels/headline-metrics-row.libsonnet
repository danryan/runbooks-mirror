local timeSeriesPanel = import 'grafonnet-dashboarding/grafana/timeseries-panel.libsonnet';

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
    lineWidth=if expectMultipleSeries then 1 else 2,
  );

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

  local apdexPanels = if showApdex then [
    [
      apdexPanel(),
    ]
    + if expectMultipleSeries then [] else [
      apdexStatusDescriptionPanel(),
    ],
  ] else [];

  local errorRatioPanels = if showErrorRatio then [
    [
      errorRatioPanel(),
    ]
    + if expectMultipleSeries then [] else [
      errorRatioStatusDescriptionPanel(),
    ],
  ] else [];

  local opsRatePanels = if showOpsRate then [
    [
      opsRatePanel(),
    ],
  ] else [];


  apdexPanels + errorRatioPanels + opsRatePanels;

function(
  serviceType,
  startRow,
  rowTitle='🌡️ Aggregated Service Level Indicators (𝙎𝙇𝙄𝙨)',
  selectorHash={},
  stableIdPrefix='',
  showApdex=true,
  apdexDescription=null,
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
  {}
