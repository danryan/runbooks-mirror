local g = import 'grafonnet-dashboarding/grafana/g.libsonnet';
local timeSeries = g.panel.timeSeries;
local defaultFieldConfig = timeSeries.fieldConfig.defaults.custom;

local stableId(stableId) = if stableId then { stableId: stableId } else {};

// in Grafonnet-lib this was called a `graphPanel`
function(
  title,
  linewidth=1,
  fill=0,
  description='',
  decimals=2,
  sort='desc',
  legend_show=true,
  legend_values=true,
  legend_min=true,
  legend_max=true,
  legend_current=true,
  legend_total=false,
  legend_avg=true,
  legend_alignAsTable=true,
  legend_hideEmpty=true,
  legend_rightSide=false,
  thresholds=[],
  points=false,
  pointradius=5,
  stableId=null,
  lines=true,
  stack=false,
  bars=false,
)
  assert bars : 'use a barchart instead https://grafana.github.io/grafonnet/API/panel/barChart/index.html';

  local legendCalcs = if legend_values then
    (if legend_current then ['lastNotNull'] else [])
    + (if legend_min then ['min'] else [])
    + (if legend_max then ['max'] else [])
    + (if legend_max then ['avg'] else [])
    + (if legend_total then ['total'] else [])
    + (if legend_values then ['values'] else [])
  else [];
  local legendPlacement = if legend_rightSide then 'right' else 'bottom';

  local defaultFieldConfigPointsMixin = if points then {
    fieldConfig+: { defaults+: { custom+: { showPoints: 'always', pointSize: pointradius } } },
  };

  local stackingConfig = if stack then defaultFieldConfig.stacking.withMode('normal') else {};

  timeSeries.new(title)
  + defaultFieldConfig.withLineWidth(linewidth)
  + defaultFieldConfig.withLineFill(fill)
  + defaultFieldConfigPointsMixin
  + timeSeries.panelOptions.withDescription(description)
  + timeSeries.standardOptions.withDecimals(decimals)
  + timeSeries.options.withLegend(
    timeSeries.options.legend.withShowLegend(legend_show)
    + timeSeries.options.legend.withWithSortDesc(sort == 'desc')
    + timeSeries.options.legend.withAsTable()
    + timeSeries.options.legend.withCalcs(legendCalcs)
    + timeSeries.options.legend.withPlacement(legendPlacement)
  )
  + stackingConfig
  + stableId(stableId)
