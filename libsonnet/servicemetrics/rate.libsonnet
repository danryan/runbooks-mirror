local metric = import './metric.libsonnet';
local aggregations = import 'promql/aggregations.libsonnet';
local selectors = import 'promql/selectors.libsonnet';
local optionalFilterExpr = import 'recording-rules/lib/optional-filter-expr.libsonnet';
local optionalOffset = import 'recording-rules/lib/optional-offset.libsonnet';
local metricLabelsSelectorsMixin = (import './metrics-mixin.libsonnet').metricLabelsSelectorsMixin;

// Generates a range-vector function using the provided functions
local generateRangeFunctionQuery(rate, rangeFunction, additionalSelectors, rangeInterval, withoutLabels, offset) =
  local selector = selectors.merge(additionalSelectors, rate.selector);
  local selectorWithout = selectors.without(selector, withoutLabels);

  '%(rangeFunction)s(%(counter)s{%(selector)s}[%(rangeInterval)s]%(optionalOffset)s)%(filterExpr)s' % {
    rangeFunction: rangeFunction,
    counter: rate.counter,
    selector: selectors.serializeHash(selectorWithout),
    rangeInterval: rangeInterval,
    optionalOffset: optionalOffset(offset),
    filterExpr: optionalFilterExpr(rate.filterExpr),
  };

{
  rateMetric(
    counter,
    selector={},
    filterExpr='',
    useRecordingRuleRegistry=true,
  ):: metric.new({
    counter: counter,
    selector: selector,
    filterExpr: filterExpr,
    useRecordingRuleRegistry:: useRecordingRuleRegistry,

    // This creates a rate query of the form
    // rate(....{<selector>}[<rangeInterval>])
    rateQuery(selector, rangeInterval, withoutLabels=[], offset=null)::
      generateRangeFunctionQuery(self, 'rate', selector, rangeInterval, withoutLabels=withoutLabels, offset=offset),

    // This creates a increase query of the form
    // increase(....{<selector>}[<rangeInterval>])
    increaseQuery(selector, rangeInterval, withoutLabels=[])::
      generateRangeFunctionQuery(self, 'increase', selector, rangeInterval, withoutLabels=withoutLabels),

    // This creates an aggregated rate query of the form
    // sum by(<aggregationLabels>) (rate(....{<selector>}[<rangeInterval>]))
    aggregatedRateQuery(aggregationLabels, selector, rangeInterval, withoutLabels=[], offset=null)::
      local combinedSelector = selectors.without(selectors.merge(self.selector, selector), withoutLabels);

      local resolvedRecordingRule = self.config.recordingRuleRegistry.resolveRecordingRuleFor(
        aggregationFunction='sum',
        aggregationLabels=aggregationLabels,
        rangeVectorFunction='rate',
        metricName=counter,
        rangeInterval=rangeInterval,
        selector=combinedSelector,
        offset=offset,
        filterExpr=filterExpr,
      );

      if !useRecordingRuleRegistry || resolvedRecordingRule == null then
        local query = generateRangeFunctionQuery(self, 'rate', selector, rangeInterval, withoutLabels, offset);
        aggregations.aggregateOverQuery('sum', aggregationLabels, query)
      else
        resolvedRecordingRule,

    // This creates an aggregated increase query of the form
    // sum by(<aggregationLabels>) (increase(....{<selector>}[<rangeInterval>]))
    aggregatedIncreaseQuery(aggregationLabels, selector, rangeInterval, withoutLabels=[])::
      local query = generateRangeFunctionQuery(self, 'increase', selector, rangeInterval, withoutLabels=withoutLabels);
      aggregations.aggregateOverQuery('sum', aggregationLabels, query),

  } + metricLabelsSelectorsMixin(selector, [counter])),

  // clampMinZero is useful for taking derivatives of poorly-behaved counters
  // that sometimes decrease, such as Elasticsearch indexing rate and Linux
  // iowait.
  // Clamping the deriv to 0 truncates these spurious spikes.
  // We must use deriv rather than rate in these cases to avoid interpreting a
  // small decrease as an increase of almost the absolute value of the counter
  // (i.e. as occurring after a counter reset).
  derivMetric(
    counter,
    selector='',
    filterExpr='',
    clampMinZero=false,
  ):: metric.new({
    counter: counter,
    selector: selector,
    filterExpr: filterExpr,
    clampMinZero: clampMinZero,
    useRecordingRuleRegistry:: false,

    // This creates a rate query of the form
    // deriv(....{<selector>}[<rangeInterval>])
    rateQuery(selector, rangeInterval, withoutLabels=[], offset=null)::
      local query = generateRangeFunctionQuery(self, 'deriv', selector, rangeInterval, withoutLabels=withoutLabels, offset=offset);
      if self.clampMinZero then
        'clamp_min(%(query)s, 0)' % { query: query }
      else
        query,

    // This creates a increase query of the form
    // increase(....{<selector>}[<rangeInterval>])
    increaseQuery(selector, rangeInterval, withoutLabels=[])::
      generateRangeFunctionQuery(self, 'increase', selector, rangeInterval, withoutLabels=withoutLabels),

    // This creates an aggregated rate query of the form
    // sum by(<aggregationLabels>) (deriv(....{<selector>}[<rangeInterval>]))
    aggregatedRateQuery(aggregationLabels, selector, rangeInterval, withoutLabels=[], offset=null)::
      local query = generateRangeFunctionQuery(self, 'deriv', selector, rangeInterval, withoutLabels=withoutLabels, offset=offset);
      local clampedQuery = if self.clampMinZero then
        'clamp_min(%(query)s, 0)' % { query: query }
      else
        query;
      aggregations.aggregateOverQuery('sum', aggregationLabels, clampedQuery),

    // This creates an aggregated increase query of the form
    // sum by(<aggregationLabels>) (increase(....{<selector>}[<rangeInterval>]))
    aggregatedIncreaseQuery(aggregationLabels, selector, rangeInterval, withoutLabels=[])::
      local query = generateRangeFunctionQuery(self, 'increase', selector, rangeInterval, withoutLabels=withoutLabels);
      aggregations.aggregateOverQuery('sum', aggregationLabels, query),

  } + metricLabelsSelectorsMixin(selector, [counter])),
}
