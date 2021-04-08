local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local promQuery = import 'grafana/prom_query.libsonnet';
local graphPanel = grafana.graphPanel;
local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local heatmapPanel = grafana.heatmapPanel;
local text = grafana.text;
local seriesOverrides = import 'grafana/series_overrides.libsonnet';
local singlestatPanel = grafana.singlestat;
local tablePanel = grafana.tablePanel;
local timepickerlib = import 'github.com/grafana/grafonnet-lib/grafonnet/timepicker.libsonnet';
local templates = import 'grafana/templates.libsonnet';
local commonAnnotations = import 'grafana/common_annotations.libsonnet';
local stableIds = import 'stable-ids/stable-ids.libsonnet';
local selectors = import 'promql/selectors.libsonnet';

local applyStableIdsToPanel(panel) =
  local recursivelyApplied = if std.objectHas(panel, 'panels') then
    panel {
      panels: std.map(function(panel) applyStableIdsToPanel(panel), panel.panels),
    }
  else
    panel;

  if std.objectHasAll(recursivelyApplied, 'stableId') then
    recursivelyApplied {
      id: stableIds.hashStableId(recursivelyApplied.stableId),
    }
  else
    recursivelyApplied;

local applyStableIdsToRow(row) =
  row {
    panels: std.map(function(panel) applyStableIdsToPanel(panel), row.panels),
  };

local applyStableIdsToDashboard(dashboard) =
  dashboard {
    rows: std.map(function(row) applyStableIdsToRow(row), dashboard.rows),
    panels: std.map(function(panel) applyStableIdsToPanel(panel), dashboard.panels),
  };

// Lists all panels under a panel
local panelsForPanel(panel) =
  local childPanels = if std.objectHas(panel, 'panels') then
    std.flatMap(function(panel) panelsForPanel(panel), panel.panels)
  else
    [];
  [panel] + childPanels;

// Lists all panels under a row
local panelsForRow(row) =
  std.flatMap(function(panel) panelsForPanel(panel), row.panels);

// Validates that each panel has a unique ID, otherwise Grafana does odd things
local validateUniqueIdsForDashboard(dashboard) =
  local rowPanels = std.flatMap(panelsForRow, dashboard.rows);
  local directPanels = std.flatMap(panelsForPanel, dashboard.panels);
  local allPanels = rowPanels + directPanels;
  local uniquePanelIds = std.foldl(
    function(memo, panel)
      local panelIdStr = '' + panel.id;
      if std.objectHas(memo, panelIdStr) then
        /**
         * If you find yourself here, the reason is that validation of your dashboard failed
         * due to duplicate IDs. The most likely reason for this is because
         * the `stableId` string for two panels hashed to the same value.
         */
        local assertFormatConfig = {
          panelId: panelIdStr,
          otherPanelTitle: memo[panelIdStr],
          panelTitle: panel.title,
        };
        std.assertEqual('', { __assert__: 'Duplicated panel ID `%(panelId)s`. This will lead to layout problems in Grafana. Titles of panels with duplicate titles are `%(otherPanelTitle)s` and `%(panelTitle)s`' % assertFormatConfig })
      else
        memo { [panelIdStr]: panel.title },
    allPanels,
    {}
  );

  // Force jsonnet to walk all panels
  if uniquePanelIds != null then
    dashboard
  else
    dashboard;

local panelOverrides(stableId) =
  {
    addDataLink(datalink):: self + {
      options+: {
        dataLinks+: [datalink],
      },
    },
  }
  +
  (
    if stableId == null then
      {}
    else
      {
        stableId: stableId,
      }
  );

local getDefaultAvailabilityColorScale(invertColors, factor) =
  local tf = if invertColors then function(value) (1 - value) * factor else function(value) value;
  local scale = [
    {
      color: 'red',
      value: tf(0),
    },
    {
      color: 'light-red',
      value: tf(0.95),
    },
    {
      color: 'orange',
      value: tf(0.99),
    },
    {
      color: 'light-orange',
      value: tf(0.995),
    },
    {
      color: 'yellow',
      value: tf(0.9994),
    },
    {
      color: 'light-yellow',
      value: tf(0.9995),
    },
    {
      color: 'green',
      value: tf(0.9998),
    },
  ];

  std.sort(scale, function(i) if i.value == null then 0 else i.value);

local latencyHistogramQuery(percentile, bucketMetric, selector, aggregator, rangeInterval) =
  |||
    histogram_quantile(%(percentile)g, sum by (%(aggregator)s, le) (
      rate(%(bucketMetric)s{%(selector)s}[%(rangeInterval)s])
    ))
  ||| % {
    percentile: percentile,
    aggregator: aggregator,
    selector: selectors.serializeHash(selector),
    bucketMetric: bucketMetric,
    rangeInterval: rangeInterval,
  };

{
  dashboard(
    title,
    tags,
    editable=false,
    time_from='now-6h/m',
    time_to='now/m',
    refresh='',
    timepicker=timepickerlib.new(),
    graphTooltip='shared_crosshair',
    hideControls=false,
    description=null,
    includeStandardEnvironmentAnnotations=true,
    includeEnvironmentTemplate=true,
  )::
    local dashboard =
      grafana.dashboard.new(
        title,
        style='light',
        schemaVersion=16,
        tags=tags,
        timezone='utc',
        graphTooltip=graphTooltip,
        editable=editable,
        refresh=refresh,
        hideControls=false,
        description=null,
        time_from=time_from,
        time_to=time_to,
      )
      .addTemplate(templates.ds);  // All dashboards include the `ds` variable

    local dashboardWithAnnotations = if includeStandardEnvironmentAnnotations then
      dashboard
      .addAnnotation(commonAnnotations.deploymentsForEnvironment)
      .addAnnotation(commonAnnotations.deploymentsForEnvironmentCanary)
      .addAnnotation(commonAnnotations.featureFlags)
    else
      dashboard;

    local dashboardWithEnvTemplate = if includeEnvironmentTemplate then
      dashboardWithAnnotations
      .addTemplate(templates.environment)
    else
      dashboardWithAnnotations;

    dashboardWithEnvTemplate {
      trailer()::
        local dashboardWithTrailerPanel = self.addPanel(
          text.new(
            title='Source',
            mode='markdown',
            content=|||
              Made with ❤️ and [Grafonnet](https://github.com/grafana/grafonnet-lib). [Contribute to this dashboard on GitLab.com](https://gitlab.com/gitlab-com/runbooks/blob/master/dashboards/%(filePath)s)
            ||| % { filePath: std.extVar('dashboardPath') },
          ),
          gridPos={
            x: 0,
            y: 110000,
            w: 24,
            h: 2,
          }
        );

        local dashboardWithStableIdsApplied = applyStableIdsToDashboard(dashboardWithTrailerPanel);
        validateUniqueIdsForDashboard(dashboardWithStableIdsApplied),
    },

  graphPanel(
    title,
    linewidth=1,
    fill=0,
    datasource='$PROMETHEUS_DS',
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
    stack=false,
  )::
    graphPanel.new(
      title=title,
      linewidth=linewidth,
      fill=fill,
      datasource=datasource,
      description=description,
      decimals=decimals,
      sort=sort,
      legend_show=legend_show,
      legend_values=legend_values,
      legend_min=legend_min,
      legend_max=legend_max,
      legend_current=legend_current,
      legend_total=legend_total,
      legend_avg=legend_avg,
      legend_alignAsTable=legend_alignAsTable,
      legend_hideEmpty=legend_hideEmpty,
      legend_rightSide=legend_rightSide,
      thresholds=thresholds,
      points=points,
      pointradius=pointradius,
      stack=stack,
    ) + panelOverrides(stableId),

  heatmap(
    title='Heatmap',
    description='',
    query='',
    legendFormat='',
    format='short',
    interval='1m',
    intervalFactor=3,
    yAxisLabel='',
    legend_show=true,
    linewidth=2,
    stableId=null,
  )::
    heatmapPanel.new(
      title,
      description=description,
      datasource='$PROMETHEUS_DS',
      legend_show=false,
      yAxis_format='s',
      color_mode='opacity',
    )
    .addTarget(promQuery.target(query, legendFormat=legendFormat, interval=interval, intervalFactor=intervalFactor))
    + panelOverrides(stableId),

  singlestat(
    title='SingleStat',
    description='',
    query='',
    colors=[
      '#299c46',
      'rgba(237, 129, 40, 0.89)',
      '#d44a3a',
    ],
    legendFormat='',
    format='percentunit',
    gaugeMinValue=0,
    gaugeMaxValue=100,
    gaugeShow=false,
    instant=true,
    interval='1m',
    intervalFactor=3,
    postfix=null,
    thresholds='',
    yAxisLabel='',
    legend_show=true,
    linewidth=2,
    valueName='current',
    stableId=null,
  )::
    singlestatPanel.new(
      title,
      description=description,
      datasource='$PROMETHEUS_DS',
      colors=colors,
      format=format,
      gaugeMaxValue=gaugeMaxValue,
      gaugeShow=gaugeShow,
      postfix=postfix,
      thresholds=thresholds,
      valueName=valueName,
    )
    .addTarget(promQuery.target(query, instant)) +
    panelOverrides(stableId),

  table(
    title='Table',
    description='',
    span=null,
    min_span=null,
    styles=[],
    columns=[],
    query='',
    instant=true,
    interval='1m',
    intervalFactor=3,
    stableId=null,
    sort=null,
  )::
    tablePanel.new(
      title,
      description=description,
      span=span,
      min_span=min_span,
      datasource='$PROMETHEUS_DS',
      styles=styles,
      columns=columns,
      sort=sort,
    )
    .addTarget(promQuery.target(query, instant=instant, format='table')) +
    panelOverrides(stableId),

  multiTimeseries(
    title='Multi timeseries',
    description='',
    queries=[],
    format='short',
    interval='1m',
    intervalFactor=3,
    yAxisLabel='',
    sort='decreasing',
    legend_show=true,
    legend_rightSide=false,
    linewidth=2,
    max=null,
    maxY2=1,
    decimals=0,
    thresholds=[],
    stableId=null,
    fill=0,
    stack=false,
  )::
    local panel = self.graphPanel(
      title,
      description=description,
      sort=sort,
      linewidth=linewidth,
      fill=fill,
      datasource='$PROMETHEUS_DS',
      decimals=decimals,
      legend_rightSide=legend_rightSide,
      legend_show=legend_show,
      legend_values=true,
      legend_min=true,
      legend_max=true,
      legend_current=true,
      legend_total=false,
      legend_avg=true,
      legend_alignAsTable=true,
      legend_hideEmpty=true,
      thresholds=thresholds,
      stableId=stableId,
      stack=stack,
    );

    local addPanelTarget(panel, query) =
      panel.addTarget(promQuery.target(query.query, legendFormat=query.legendFormat, interval=interval, intervalFactor=intervalFactor));

    std.foldl(addPanelTarget, queries, panel)
    .resetYaxes()
    .addYaxis(
      format=format,
      min=0,
      max=max,
      label=yAxisLabel,
    )
    .addYaxis(
      format='short',
      max=maxY2,
      min=0,
      show=false,
    ),

  timeseries(
    title='Timeseries',
    description='',
    query='',
    legendFormat='',
    format='short',
    interval='1m',
    intervalFactor=3,
    yAxisLabel='',
    sort='decreasing',
    legend_show=true,
    legend_rightSide=false,
    linewidth=2,
    decimals=0,
    max=null,
    maxY2=1,
    thresholds=[],
    stableId=null,
    fill=0,
    stack=false,
  )::
    self.multiTimeseries(
      queries=[{ query: query, legendFormat: legendFormat }],
      title=title,
      description=description,
      format=format,
      interval=interval,
      intervalFactor=intervalFactor,
      yAxisLabel=yAxisLabel,
      sort=sort,
      legend_show=legend_show,
      legend_rightSide=legend_rightSide,
      linewidth=linewidth,
      max=max,
      maxY2=maxY2,
      decimals=decimals,
      thresholds=thresholds,
      stableId=stableId,
      fill=fill,
      stack=stack,
    ),

  queueLengthTimeseries(
    title='Timeseries',
    description='',
    query='',
    legendFormat='',
    format='short',
    interval='1m',
    intervalFactor=3,
    yAxisLabel='Queue Length',
    linewidth=2,
    stableId=null,
  )::
    self.graphPanel(
      title,
      description=description,
      sort='decreasing',
      linewidth=linewidth,
      fill=0,
      datasource='$PROMETHEUS_DS',
      decimals=0,
      legend_show=true,
      legend_values=true,
      legend_min=true,
      legend_max=true,
      legend_current=true,
      legend_total=false,
      legend_avg=true,
      legend_alignAsTable=true,
      legend_hideEmpty=true,
      stableId=stableId,
    )
    .addTarget(promQuery.target(query, legendFormat=legendFormat, interval=interval, intervalFactor=intervalFactor))
    .resetYaxes()
    .addYaxis(
      format=format,
      min=0,
      label=yAxisLabel,
    )
    .addYaxis(
      format='short',
      max=1,
      min=0,
      show=false,
    ),

  percentageTimeseries(
    title,
    description='',
    query='',
    legendFormat='',
    yAxisLabel='Percent',
    interval='1m',
    intervalFactor=3,
    linewidth=2,
    fill=0,
    legend_show=true,
    min=null,
    max=null,
    decimals=0,
    thresholds=null,
    stableId=null,
    stack=false
  )::
    local formatConfig = {
      query: query,
    };
    self.graphPanel(
      title,
      description=description,
      sort='decreasing',
      linewidth=linewidth,
      fill=fill,
      datasource='$PROMETHEUS_DS',
      decimals=decimals,
      legend_show=legend_show,
      legend_values=true,
      legend_min=true,
      legend_max=true,
      legend_current=true,
      legend_total=false,
      legend_avg=true,
      legend_alignAsTable=true,
      legend_hideEmpty=true,
      thresholds=thresholds,
      stableId=stableId,
      stack=stack,
    )
    .addTarget(
      promQuery.target(
        |||
          clamp_min(clamp_max(%(query)s,1),0)
        ||| % formatConfig,
        legendFormat=legendFormat,
        interval=interval,
        intervalFactor=intervalFactor
      )
    )
    .resetYaxes()
    .addYaxis(
      format='percentunit',
      min=min,
      max=max,
      label=yAxisLabel,
    )
    .addYaxis(
      format='short',
      max=1,
      min=0,
      show=false,
    ),

  saturationTimeseries(
    title='Saturation',
    description='',
    query='',
    legendFormat='',
    yAxisLabel='Saturation',
    interval='1m',
    intervalFactor=3,
    linewidth=2,
    legend_show=true,
    min=0,
    max=1,
    stableId=null,
  )::
    self.percentageTimeseries(
      title=title,
      description=description,
      query=query,
      legendFormat=legendFormat,
      yAxisLabel=yAxisLabel,
      interval=interval,
      intervalFactor=intervalFactor,
      linewidth=linewidth,
      legend_show=legend_show,
      min=min,
      max=max,
      stableId=stableId,
    ),

  apdexTimeseries(
    title='Apdex',
    description='Apdex is a measure of requests that complete within an acceptable threshold duration. Actual threshold vary per service or endpoint. Higher is better.',
    query='',
    legendFormat='',
    yAxisLabel='% Requests w/ Satisfactory Latency',
    interval='1m',
    intervalFactor=3,
    linewidth=2,
    min=null,
    legend_show=true,
    stableId=null,
  )::
    local formatConfig = {
      query: query,
    };
    self.graphPanel(
      title,
      description=description,
      sort='increasing',
      linewidth=linewidth,
      fill=0,
      datasource='$PROMETHEUS_DS',
      decimals=0,
      legend_show=legend_show,
      legend_values=true,
      legend_min=true,
      legend_max=true,
      legend_current=true,
      legend_total=false,
      legend_avg=true,
      legend_alignAsTable=true,
      legend_hideEmpty=true,
      stableId=stableId,
    )
    .addTarget(
      promQuery.target(
        |||
          clamp_min(clamp_max(%(query)s,1),0)
        ||| % formatConfig,
        legendFormat=legendFormat,
        interval=interval,
        intervalFactor=intervalFactor
      )
    )
    .resetYaxes()
    .addYaxis(
      format='percentunit',
      min=min,
      max=1,
      label=yAxisLabel,
    )
    .addYaxis(
      format='short',
      max=1,
      min=0,
      show=false,
    ),

  latencyTimeseries(
    title='Latency',
    description='',
    query='',
    legendFormat='',
    format='s',
    yAxisLabel='Duration',
    interval='1m',
    intervalFactor=3,
    legend_show=true,
    logBase=1,
    decimals=2,
    linewidth=2,
    min=0,
    stableId=null,
  )::
    self.graphPanel(
      title,
      description=description,
      sort='decreasing',
      linewidth=linewidth,
      fill=0,
      datasource='$PROMETHEUS_DS',
      decimals=decimals,
      legend_show=legend_show,
      legend_values=true,
      legend_min=true,
      legend_max=true,
      legend_current=true,
      legend_total=false,
      legend_avg=true,
      legend_alignAsTable=true,
      legend_hideEmpty=true,
      stableId=stableId,
    )
    .addTarget(promQuery.target(query, legendFormat=legendFormat, interval=interval, intervalFactor=intervalFactor))
    .resetYaxes()
    .addYaxis(
      format=format,
      min=min,
      label=yAxisLabel,
      logBase=logBase,
    )
    .addYaxis(
      format='short',
      max=1,
      min=0,
      show=false,
    ),

  slaTimeseries(
    title='SLA',
    description='',
    query='',
    legendFormat='',
    yAxisLabel='SLA',
    interval='1m',
    intervalFactor=3,
    points=false,
    pointradius=3,
    stableId=null,
    legend_show=true,
  )::
    local formatConfig = {
      query: query,
    };
    self.graphPanel(
      title,
      description=description,
      sort='decreasing',
      linewidth=2,
      fill=0,
      datasource='$PROMETHEUS_DS',
      decimals=2,
      legend_show=legend_show,
      legend_values=true,
      legend_min=true,
      legend_max=true,
      legend_current=true,
      legend_total=false,
      legend_avg=true,
      legend_alignAsTable=true,
      legend_hideEmpty=true,
      points=points,
      pointradius=pointradius,
      stableId=stableId,
    )
    .addTarget(
      promQuery.target(
        |||
          clamp_min(clamp_max(%(query)s,1),0)
        ||| % formatConfig,
        legendFormat=legendFormat,
        interval=interval,
        intervalFactor=intervalFactor,
      )
    )
    .resetYaxes()
    .addYaxis(
      format='percentunit',
      max=1,
      label=yAxisLabel,
    )
    .addYaxis(
      format='short',
      max=1,
      min=0,
      show=false,
    ),

  multiQuantileTimeseries(
    title='Quantile latencies',
    selector='',
    legendFormat='latency',
    bucketMetric='',
    aggregators='',
    percentiles=[50, 90, 95, 99],
  )::
    local queries = std.map(
      function(p) {
        query: latencyHistogramQuery(p / 100, bucketMetric, selector, aggregators, '$__interval'),
        legendFormat: '%s p%s' % [legendFormat, p],
      },
      percentiles
    );

    self.multiTimeseries(title=title, decimals=2, queries=queries, yAxisLabel='Duration', format='s'),

  networkTrafficGraph(
    title='Node Network Utilization',
    description='Network utilization',
    sendQuery=null,
    legendFormat='{{ fqdn }}',
    receiveQuery=null,
    intervalFactor=3,
    legend_show=true,
    stableId=null,
  )::
    self.graphPanel(
      title,
      linewidth=1,
      fill=0,
      description=description,
      datasource='$PROMETHEUS_DS',
      decimals=2,
      sort='decreasing',
      legend_show=legend_show,
      legend_values=false,
      legend_alignAsTable=false,
      legend_hideEmpty=true,
      stableId=stableId,
    )
    .addSeriesOverride(seriesOverrides.networkReceive)
    .addTarget(
      promQuery.target(
        sendQuery,
        legendFormat='send ' + legendFormat,
        intervalFactor=intervalFactor,
      )
    )
    .addTarget(
      promQuery.target(
        receiveQuery,
        legendFormat='receive ' + legendFormat,
        intervalFactor=intervalFactor,
      )
    )
    .resetYaxes()
    .addYaxis(
      format='Bps',
      label='Network utilization',
    )
    .addYaxis(
      format='short',
      max=1,
      min=0,
      show=false,
    ),

  slaStats(
    title,
    description='Availability',
    query=null,
    fieldTitle='',
    legendFormat='',
    displayName=null,
    links=[],
    stableId=null,
    decimals=2,
    invertColors=false,
    unit='percentunit',
  )::
    {
      datasource: '$PROMETHEUS_DS',
      targets: [promQuery.target(query, legendFormat=legendFormat, instant=true)],
      title: title,
      type: 'stat',
      pluginVersion: '7.0.3',
      options: {
        reduceOptions: {
          values: true,
          calcs: [
            'last',
          ],
          fields: '',
        },
        orientation: 'auto',
        colorMode: 'background',
        graphMode: 'none',
        justifyMode: 'auto',
      },
      fieldConfig: {
        defaults: {
          custom: {},
          unit: unit,
          min: 0,
          max: 1,
          decimals: decimals,
          displayName: displayName,
          thresholds: {
            mode: 'absolute',
            steps: getDefaultAvailabilityColorScale(invertColors, if unit == 'percentunit' then 1 else 100),
          },
          mappings: [],
          links: links,
          color: {
            mode: 'thresholds',
          },
        },
        overrides: [],
      },
    } +
    panelOverrides(stableId),

  // This is a useful hack for displaying a label value in a stat panel
  labelStat(
    query,
    title,
    panelTitle,
    color,
    legendFormat,
    links=[],
    stableId=null,
  )::
    {
      type: 'stat',
      title: panelTitle,
      targets: [promQuery.target(query, legendFormat=legendFormat, instant=true)],
      pluginVersion: '6.6.1',
      links: [],
      options: {
        graphMode: 'none',
        colorMode: 'background',
        justifyMode: 'auto',
        fieldOptions: {
          values: false,
          calcs: [
            'lastNotNull',
          ],
          defaults: {
            thresholds: {
              mode: 'absolute',
              steps: [
                {
                  value: null,
                  color: color,
                },
              ],
            },
            mappings: [
              {
                value: 'null',
                op: '=',
                text: title,
                id: 0,
                type: 2,
                from: '-10000000',
                to: '10000000',
              },
            ],
            unit: 'none',
            nullValueMode: 'connected',
            title: '${__series.name}',
            links: links,
          },
          overrides: [],
        },
        orientation: 'vertical',
      },
    } + panelOverrides(stableId),

  statPanel(
    title,
    panelTitle,
    color,
    query,
    legendFormat,
    unit='',
    decimals=0,
    instant=true,
  )::
    local steps = if std.type(color) == 'string' then
      [
        {
          color: color,
          value: null,
        },
      ] else
      color;
    {
      links: [],
      options: {
        graphMode: 'none',
        colorMode: 'background',
        justifyMode: 'auto',
        fieldOptions: {
          values: false,
          calcs: [
            'lastNotNull',
          ],
          defaults: {
            thresholds: {
              mode: 'absolute',
              steps: steps,
            },
            mappings: [],
            title: title,
            unit: unit,
            decimals: decimals,
          },
          overrides: [],
        },
        orientation: 'vertical',
      },
      pluginVersion: '6.6.1',
      targets: [promQuery.target(query, legendFormat=legendFormat, instant=instant)],
      title: panelTitle,
      type: 'stat',
    },
}
