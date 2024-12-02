local intervalForDuration = import 'servicemetrics/interval-for-duration.libsonnet';
local monitoredServices = (import 'gitlab-metrics-config.libsonnet').monitoredServices;
local aggregationSets = (import 'gitlab-metrics-config.libsonnet').aggregationSets;

local aggregationSet = import 'servicemetrics/aggregation-set.libsonnet';
local sliMetricDescriptor = import 'servicemetrics/sli_metric_descriptor.libsonnet';
local selectors = import 'promql/selectors.libsonnet';
local aggregations = import 'promql/aggregations.libsonnet';
local optionalOffset = import 'recording-rules/lib/optional-offset.libsonnet';
local optionalFilterExpr = import 'recording-rules/lib/optional-filter-expr.libsonnet';
local metricsConfig = import 'gitlab-metrics-config.libsonnet';
local metricsCatalog = import 'servicemetrics/metrics-catalog.libsonnet';

local aggregationSetLabels = std.set(
  std.flatMap(
    function(set) set.labels,
    std.objectValues(aggregationSets)
  )
);

local injectAggregationSetLabels(metricAndLabelsHash) =
  std.foldl(
    function(memo, metric)
      memo { [metric]: std.setUnion(metricAndLabelsHash[metric], aggregationSetLabels) },
    std.objectFields(metricAndLabelsHash),
    {}
  );

local recordedMetricNamesAndLabelsByType =
  std.foldl(
    function(memo, serviceDefinition)
      memo {
        [serviceDefinition.type]: sliMetricDescriptor.collectMetricNamesAndLabels(
          [
            injectAggregationSetLabels(
              sliMetricDescriptor.sliMetricsDescriptor(serviceDefinition.listServiceLevelIndicators()).aggregationLabelsByMetric
            ),
          ]
        ),
      },
    monitoredServices,
    {}
  );

local recordingRuleExpressionFor(metricName, labels, selector, burnRate) =
  local query = 'rate(%(metricName)s{%(selector)s}[%(rangeInterval)s] offset 30s)' % {
    metricName: metricName,
    rangeInterval: burnRate,
    selector: selectors.serializeHash(selector),
  };
  aggregations.aggregateOverQuery('sum', std.setUnion(labels, aggregationSetLabels), query);

local recordingRuleNameFor(metricName, burnRate) =
  'sli_aggregations:%(metricName)s:rate_%(rangeInterval)s' % {
    metricName: metricName,
    rangeInterval: burnRate,
  };

local generateRecordingRulesForMetric(metricName, labels, selector, burnRate) =
  {
    record: recordingRuleNameFor(metricName, burnRate),
    expr: recordingRuleExpressionFor(metricName, labels, selector, burnRate),
  };

local splitAggregationString(aggregationLabelsString) =
  if aggregationLabelsString == '' then
    []
  else
    [
      std.stripChars(str, ' \n\t')
      for str in std.split(aggregationLabelsString, ',')
    ];

local resolveRecordingRuleFor(metricName, aggregationLabels, selector, rangeInterval) =
  // Recording rules can't handle `$__interval` or $__rate_interval variable ranges, so always resolve these as 5m
  local durationWithRecordingRule = if std.startsWith(rangeInterval, '$__') then '5m' else rangeInterval;
  assert std.setMember(durationWithRecordingRule, std.set(aggregationSet.defaultSourceBurnRates)) : 'unsupported burn rate: %s' % [rangeInterval];

  local allMetricNamesAndLabels = sliMetricDescriptor.collectMetricNamesAndLabels(std.objectValues(recordedMetricNamesAndLabelsByType));
  local recordedLabels = allMetricNamesAndLabels[metricName];

  local aggregationLabelsArray = if std.isArray(aggregationLabels) then
    aggregationLabels
  else
    splitAggregationString(aggregationLabels);

  // monitor is added in thanos, but not in prometheus.
  // In mimir it should not matter either as everything is global (but per tenant)
  local ignoredLabels = ['monitor'];
  local requiredLabelsWithIgnoredLabels = std.set(aggregationLabelsArray + selectors.getLabels(selector));
  local requiredLabels = std.setDiff(requiredLabelsWithIgnoredLabels, ignoredLabels);

  local missingLabels = std.setDiff(requiredLabels, recordedLabels);
  assert std.length(missingLabels) == 0 : '%s labels are missing in the SLI aggregations for %s' % [missingLabels, metricName];

  '%(metricName)s{%(selector)s}' % {
    metricName: recordingRuleNameFor(metricName, durationWithRecordingRule),
    selector: selectors.serializeHash(selector),
  };

local generateRuleGroupForMetrics(metrics, metricGroupName, serviceDefinition, emittingType, descriptor, extraSelector, burnRate, cluster=null) =
  local rules = std.map(
    function(metricName)
      local aggregationLabels = descriptor.aggregationLabelsByMetric[metricName];
      local selectorsByMetric = descriptor.selectorsByMetric;
      local selector = selectors.merge(
        selectorsByMetric[metricName],
        extraSelector
      );
      generateRecordingRulesForMetric(metricName, aggregationLabels, selector, burnRate),
    metrics
  );
  {
    name: 'SLI Aggregations: %(serviceName)s - %(metricGroupName)s - %(burnRate)s burn-rate%(emittedBy)s%(clusterOptional)s' % {
      serviceName: serviceDefinition.type,
      metricGroupName: metricGroupName,
      burnRate: burnRate,
      emittedBy: if emittingType != null && emittingType != serviceDefinition.type then ' - emitted by %s' % emittingType else '',
      clusterOptional: if cluster != null then ' - %s' % cluster else '',
    },
    interval: intervalForDuration.intervalForDuration(burnRate),
    rules: rules,
  };

local ruleGroupsForClustersForMetrics(clusters, descriptor, serviceDefinition, emittingType, metricGroupName, metrics, extraSelector, burnRate) =
  if std.length(clusters) > 0 then
    std.map(
      function(cluster)
        local extraSelectorWithCluster = selectors.merge(extraSelector, { cluster: cluster });
        generateRuleGroupForMetrics(metrics, metricGroupName, serviceDefinition, emittingType, descriptor, extraSelectorWithCluster, burnRate, cluster),
      clusters,
    )
  else
    [generateRuleGroupForMetrics(metrics, metricGroupName, serviceDefinition, emittingType, descriptor, extraSelector, burnRate)];

local ruleGroupsForTypesForMetrics(emittingTypes, descriptor, serviceDefinition, metricGroupName, metrics, burnRate, extraSelector) =
  std.flatMap(
    function(emittingType)
      local emittingServiceDefinition = metricsCatalog.getServiceOptional(emittingType);
      local isKubeProvisioned = emittingServiceDefinition != null && emittingServiceDefinition.provisioning.kubernetes;
      local env = std.get(extraSelector, 'env');
      local clusters = if env != null && isKubeProvisioned then
        std.get(metricsConfig.gkeClustersByEnvironment, env, default=[])
      else
        [];
      local extraSelectorWithType = selectors.merge(
        extraSelector,
        { type: { oneOf: [emittingType] } }
      );
      ruleGroupsForClustersForMetrics(
        clusters, descriptor, serviceDefinition, emittingType, metricGroupName, metrics, extraSelectorWithType, burnRate
      ),
    emittingTypes
  );

local ruleGroupsForMetrics(metrics, descriptor, metricGroupName, serviceDefinition, descriptor, burnRate, extraSelector) =
  local emittingTypesByMetric = descriptor.emittingTypesByMetric;
  local metric = metrics[0];
  local emittingTypes = emittingTypesByMetric[metric];

  if std.length(emittingTypes) > 0 then
    ruleGroupsForTypesForMetrics(emittingTypes, descriptor, serviceDefinition, metricGroupName, metrics, burnRate, extraSelector)
  else
    [generateRuleGroupForMetrics(metrics, metricGroupName, serviceDefinition, null, descriptor, extraSelector, burnRate)];

local generateRecordingRuleGroups(serviceDefinition, burnRate, extraSelector) =
  local descriptor = sliMetricDescriptor.sliMetricsDescriptor(serviceDefinition.listServiceLevelIndicators());

  std.flatMap(
    function(metricGroupName)
      ruleGroupsForMetrics(descriptor.allMetricGroups[metricGroupName], descriptor, metricGroupName, serviceDefinition, descriptor, burnRate, extraSelector),
    std.objectFields(descriptor.allMetricGroups),
  );

{
  resolveRecordingRuleFor(
    aggregationFunction='sum',
    aggregationLabels=[],
    rangeVectorFunction='rate',
    metricName=null,
    rangeInterval='5m',
    selector={},
    offset=null,
    filterExpr=''
  )::
    if rangeVectorFunction != 'rate' then null
    else
      local resolvedRecordingRule = resolveRecordingRuleFor(metricName, aggregationLabels, selector, rangeInterval);
      local recordingRuleWithOffset = resolvedRecordingRule + optionalOffset(offset);
      local recordingRule = recordingRuleWithOffset + optionalFilterExpr(filterExpr);
      if aggregationFunction == 'sum' then
        aggregations.aggregateOverQuery(aggregationFunction, aggregationLabels, recordingRule)
      else if aggregationFunction == null then
        recordingRule
      else
        assert false : 'unsupported aggregation %s' % [aggregationFunction];
        null,

  ruleGroupsForServiceForBurnRate(serviceDefinition, burnRate, extraSelector)::
    generateRecordingRuleGroups(
      serviceDefinition,
      burnRate,
      extraSelector
    ),

  recordingRuleForMetricAtBurnRate(metricName, rangeInterval)::
    local metricNames = std.flatMap(std.objectFields, std.objectValues(recordedMetricNamesAndLabelsByType));

    std.setMember(metricName, metricNames),

  recordingRuleNameFor: recordingRuleNameFor,
}
