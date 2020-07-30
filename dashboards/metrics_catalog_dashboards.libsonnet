local basic = import 'grafana/basic.libsonnet';
local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local keyMetrics = import 'key_metrics.libsonnet';
local layout = import 'grafana/layout.libsonnet';
local metricsCatalog = import 'metrics-catalog.libsonnet';
local thresholds = import 'thresholds.libsonnet';
local row = grafana.row;
local selectors = import 'promql/selectors.libsonnet';
local statusDescription = import 'status_description.libsonnet';

local defaultEnvironmentSelector = { environment: '$environment' };

local getLatencyPercentileForService(service) =
  if std.objectHas(service, 'contractualThresholds') && std.objectHas(service.contractualThresholds, 'apdexRatio') then
    service.contractualThresholds.apdexRatio
  else
    0.95;

local componentOverviewMatrixRow(
  serviceType,
  serviceStage,
  componentName,
  component,
  startRow,
  environmentSelectorHash,
  includeNodeLevelMonitoring=false
      ) =
  local componentSelectorHash = environmentSelectorHash { type: serviceType, stage: serviceStage, component: componentName };
  local columns =
    (
      // Component apdex
      if component.hasApdex() then
        [[
          keyMetrics.singleComponentApdexPanel(serviceType, serviceStage, componentName, environmentSelectorHash),
          statusDescription.componentApdexStatusDescriptionPanel(componentSelectorHash),
        ]]
      else
        []
    )
    +
    (
      // Error rate
      if component.hasErrorRate() then
        [[
          keyMetrics.singleComponentErrorRates(serviceType, serviceStage, componentName, environmentSelectorHash),
          statusDescription.componentErrorRateStatusDescriptionPanel(componentSelectorHash),
        ]]
      else
        []
    )
    +
    (
      // Component request rate (mandatory, but not all are aggregatable)
      if component.hasAggregatableRequestRate() then
        [[
          keyMetrics.singleComponentQPSPanel(serviceType, serviceStage, componentName, environmentSelectorHash),
        ]]
      else
        []
    );

  layout.splitColumnGrid(columns, [7, 1], startRow=startRow) +
  (
    if includeNodeLevelMonitoring then
      layout.singleRow(
        (
          if component.hasApdex() then
            [
              keyMetrics.singleComponentNodeApdexPanel(serviceType, serviceStage, componentName, environmentSelectorHash)
            ]
          else []
        )
        +
        (
          if component.hasErrorRate() then
            [
              keyMetrics.singleComponentNodeErrorRates(serviceType, serviceStage, componentName, environmentSelectorHash),
            ]
          else []
        )
        +
        (
          if component.hasAggregatableRequestRate() then
            [
              keyMetrics.singleComponentNodeQPSPanel(serviceType, serviceStage, componentName, environmentSelectorHash),
            ]
          else []
        ),
        rowHeight=5, startRow=startRow+8
      )
    else []
  );

{
  componentLatencyPanel(
    title=null,
    serviceType=null,
    componentName=null,
    selector=null,
    aggregationLabels='',
    logBase=10,
    legendFormat='%(percentile_humanized)s %(componentName)s',
    min=0.01,
    intervalFactor=2,
  )::
    local service = metricsCatalog.getService(serviceType);
    local component = service.components[componentName];
    local percentile = getLatencyPercentileForService(service);
    local formatConfig = { percentile_humanized: 'p%g' % [percentile * 100], componentName: componentName };

    basic.latencyTimeseries(
      title=(if title == null then 'Estimated %(percentile_humanized)s latency for %(componentName)s' + componentName else title) % formatConfig,
      query=component.apdex.percentileLatencyQuery(
        percentile=percentile,
        aggregationLabels=aggregationLabels,
        selector=selector,
        rangeInterval='$__interval',
      ),
      logBase=logBase,
      legendFormat=legendFormat % formatConfig,
      min=min,
      intervalFactor=intervalFactor,
    ) + {
      thresholds: [
        thresholds.errorLevel('gt', component.apdex.toleratedThreshold),
        thresholds.warningLevel('gt', component.apdex.satisfiedThreshold),
      ],
    },

  componentRPSPanel(
    title=null,
    serviceType=null,
    componentName=null,
    selector=null,
    aggregationLabels='',
    legendFormat='%(componentName)s errors',
    intervalFactor=2,
  )::
    local service = metricsCatalog.getService(serviceType);
    local component = service.components[componentName];

    basic.timeseries(
      title=if title == null then 'RPS for ' + componentName else title,
      query=component.requestRate.aggregatedRateQuery(
        aggregationLabels=aggregationLabels,
        selector=selector,
        rangeInterval='$__interval',
      ),
      legendFormat=legendFormat % { componentName: componentName },
      intervalFactor=intervalFactor,
      yAxisLabel='Requests per Second'
    ),


  componentErrorsPanel(
    title=null,
    serviceType=null,
    componentName=null,
    selector=null,
    aggregationLabels='',
    legendFormat='%(componentName)s errors',
    intervalFactor=2,
  )::
    local service = metricsCatalog.getService(serviceType);
    local component = service.components[componentName];

    basic.timeseries(
      title=if title == null then 'Errors for ' + componentName else title,
      query=component.errorRate.aggregatedIncreaseQuery(
        aggregationLabels=aggregationLabels,
        selector=selector,
        rangeInterval='$__interval',
      ),
      legendFormat=legendFormat % { componentName: componentName },
      intervalFactor=intervalFactor,
      yAxisLabel='Errors'
    ),

  componentOverviewMatrix(
    serviceType,
    serviceStage,
    startRow,
    environmentSelectorHash=defaultEnvironmentSelector,
    includeNodeLevelMonitoring=false,
  )::
    local service = metricsCatalog.getService(serviceType);
    [
      row.new(title='🔬 Component Level Indicators', collapse=false) { gridPos: { x: 0, y: startRow, w: 24, h: 1 } },
    ] +
    std.prune(
      std.flattenArrays(
        std.mapWithIndex(
          function(i, componentName)
            componentOverviewMatrixRow(
              serviceType,
              serviceStage,
              componentName,
              service.components[componentName],
              startRow=startRow + 1 + i * 10,
              environmentSelectorHash=environmentSelectorHash,
              includeNodeLevelMonitoring=includeNodeLevelMonitoring
            ), std.objectFields(service.components)
        )
      )
    ),

  componentDetailMatrix(
    serviceType,
    componentName,
    selectorHash,
    aggregationSets,
    minLatency=0.01
  )::
    local service = metricsCatalog.getService(serviceType);
    local component = service.components[componentName];
    local colCount =
      (if component.hasApdex() then 1 else 0) +
      (if component.hasAggregatableRequestRate() then 1 else 0) +
      (if component.hasErrorRate() then 1 else 0);

    local staticLabelNames = if std.objectHas(component, 'staticLabels') then std.objectFields(component.staticLabels) else [];

    // Note that we always want to ignore `type` filters, since the metricsCatalog selectors will
    // already have correctly filtered labels to ensure the right values, and if we inject the type
    // we may lose metrics 'proxied' from nodes with other types
    local filteredSelectorHash = selectors.without(selectorHash, [
      'type',
    ] + staticLabelNames);

    row.new(title='🔬 %(componentName)s Component Detail' % { componentName: componentName }, collapse=true)
    .addPanels(
      layout.grid(
        std.prune(
          std.flattenArrays(
            std.map(
              function(aggregationSet)
                [
                  if component.hasApdex() then
                    self.componentLatencyPanel(
                      title='Estimated %(percentile_humanized)s ' + componentName + ' Latency - ' + aggregationSet.title,
                      serviceType=serviceType,
                      componentName=componentName,
                      selector=filteredSelectorHash,
                      legendFormat='%(percentile_humanized)s ' + aggregationSet.legendFormat,
                      aggregationLabels=aggregationSet.aggregationLabels,
                      min=minLatency,
                    )
                  else
                    null,

                  if component.hasErrorRate() then
                    self.componentErrorsPanel(
                      title=componentName + ' Errors - ' + aggregationSet.title,
                      serviceType=serviceType,
                      componentName=componentName,
                      legendFormat=aggregationSet.legendFormat,
                      aggregationLabels=aggregationSet.aggregationLabels,
                      selector=filteredSelectorHash,
                    )
                  else
                    null,

                  if component.hasAggregatableRequestRate() then
                    self.componentRPSPanel(
                      title=componentName + ' RPS - ' + aggregationSet.title,
                      serviceType=serviceType,
                      componentName=componentName,
                      selector=filteredSelectorHash,
                      legendFormat=aggregationSet.legendFormat,
                      aggregationLabels=aggregationSet.aggregationLabels
                    )
                  else
                    null,
                ],
              aggregationSets
            )
          )
        ), cols=if colCount == 1 then 2 else colCount
      )
    ),

  autoDetailRows(serviceType, selectorHash, startRow)::
    local s = self;
    local service = metricsCatalog.getService(serviceType);

    layout.grid(
      std.mapWithIndex(
        function(i, componentName)
          local component = service.components[componentName];
          local aggregationSets =
            [
              { title: 'Overall', aggregationLabels: '', legendFormat: 'overall' },
            ] +
            std.map(function(c) { title: 'per ' + c, aggregationLabels: c, legendFormat: '{{' + c + '}}' }, component.significantLabels);

          s.componentDetailMatrix(serviceType, componentName, selectorHash, aggregationSets),
        std.objectFields(service.components)
      )
      , cols=1, startRow=startRow
    ),
}
