local aggregations = import 'promql/aggregations.libsonnet';
local selectors = import 'promql/selectors.libsonnet';
local recordingRuleRegistry = import 'recording-rule-registry.libsonnet';  // TODO: fix circular dependency
local strings = import 'utils/strings.libsonnet';

// A general apdex query is:
//
// 1. Some kind of satisfaction query (with a single threshold, a
//    double threshold, or even a combination of thresholds or-ed
//    together)
// 2. Divided by an optional denominator (when it's a double threshold
//    query; see
//    https://prometheus.io/docs/practices/histograms/#apdex-score)
// 3. Divided by some kind of weight score (either a single weight, or a
//    combination of weights or-ed together).
//
// The other functions here all use this to generate the final apdex
// query.

local generateApdexComponentRateQuery(histogramApdex, additionalSelectors, rangeInterval, leSelector={}, aggregationFunction=null, aggregationLabels=[]) =
  local selector = selectors.merge(histogramApdex.selector, additionalSelectors);
  local selectorWithLe = selectors.merge(selector, leSelector);

  local resolvedRecordingRule = recordingRuleRegistry.resolveRecordingRuleFor(
    aggregationFunction=aggregationFunction,
    aggregationLabels=aggregationLabels,
    rangeVectorFunction='rate',
    metricName=histogramApdex.histogram,
    rangeInterval=rangeInterval,
    selector=selectorWithLe,
  );

  if resolvedRecordingRule == null then
    local query = 'rate(%(histogram)s{%(selector)s}[%(rangeInterval)s])' % {
      histogram: histogramApdex.histogram,
      selector: selectors.serializeHash(selectorWithLe),
      rangeInterval: rangeInterval,
    };

    if aggregationFunction == null then
      query
    else
      aggregations.aggregateOverQuery(aggregationFunction, aggregationLabels, query)
  else
    resolvedRecordingRule;

// A double threshold apdex score only has both SATISFACTORY threshold and TOLERABLE thresholds
local generateDoubleThresholdApdexNumeratorQuery(histogramApdex, additionalSelectors, rangeInterval, aggregationFunction=null, aggregationLabels=[]) =
  local satisfiedQuery = generateApdexComponentRateQuery(histogramApdex, additionalSelectors, rangeInterval, { le: histogramApdex.satisfiedThreshold }, aggregationFunction=aggregationFunction, aggregationLabels=aggregationLabels);
  local toleratedQuery = generateApdexComponentRateQuery(histogramApdex, additionalSelectors, rangeInterval, { le: histogramApdex.toleratedThreshold }, aggregationFunction=aggregationFunction, aggregationLabels=aggregationLabels);

  |||
    (
      %(satisfied)s
      +
      %(tolerated)s
    )
    /
    2
  ||| % {
    satisfied: strings.indent(satisfiedQuery, 2),
    tolerated: strings.indent(toleratedQuery, 2),
  };

local generateApdexNumeratorQuery(histogramApdex, additionalSelectors, rangeInterval, aggregationFunction=null, aggregationLabels=[], histogramRates=false) =
  if histogramRates then
    generateApdexComponentRateQuery(histogramApdex, additionalSelectors, rangeInterval, {}, aggregationFunction=aggregationFunction, aggregationLabels=aggregationLabels)
  else if histogramApdex.toleratedThreshold == null then
    // A single threshold apdex score only has a SATISFACTORY threshold, no TOLERABLE threshold
    generateApdexComponentRateQuery(histogramApdex, additionalSelectors, rangeInterval, { le: histogramApdex.satisfiedThreshold }, aggregationFunction=aggregationFunction, aggregationLabels=aggregationLabels)
  else
    generateDoubleThresholdApdexNumeratorQuery(histogramApdex, additionalSelectors, rangeInterval, aggregationFunction=aggregationFunction, aggregationLabels=aggregationLabels);

local generateApdexScoreQuery(histogramApdex, aggregationLabels, additionalSelectors, rangeInterval, aggregationFunction=null) =
  local numeratorQuery = generateApdexNumeratorQuery(histogramApdex, additionalSelectors, rangeInterval, aggregationFunction=aggregationFunction, aggregationLabels=aggregationLabels);
  local weightQuery = generateApdexComponentRateQuery(histogramApdex, additionalSelectors, rangeInterval, { le: '+Inf' }, aggregationFunction=aggregationFunction, aggregationLabels=aggregationLabels);

  |||
    %(numeratorQuery)s
    /
    (
      %(weightQuery)s > 0
    )
  ||| % {
    numeratorQuery: strings.chomp(numeratorQuery),
    weightQuery: strings.indent(strings.chomp(weightQuery), 2),
  };

local generatePercentileLatencyQuery(histogram, percentile, aggregationLabels, additionalSelectors, rangeInterval) =
  local aggregationLabelsWithLe = aggregations.join([aggregationLabels, 'le']);
  local aggregatedRateQuery = generateApdexComponentRateQuery(histogram, additionalSelectors, rangeInterval, aggregationFunction='sum', aggregationLabels=aggregationLabelsWithLe);

  |||
    histogram_quantile(
      %(percentile)f,
      %(aggregatedRateQuery)s
    )
  ||| % {
    percentile: percentile,
    aggregatedRateQuery: strings.indent(strings.chomp(aggregatedRateQuery), 2),
  };


local generateApdexAttributionQuery(histogram, selector, rangeInterval, aggregationLabel) =
  |||
    (
      %(splitTotalQuery)s
      -
      (
        %(numeratorQuery)s
      )
    )
    / ignoring(%(aggregationLabel)s) group_left()
    (
      %(aggregatedTotalQuery)s
    )

  ||| % {
    splitTotalQuery: generateApdexComponentRateQuery(histogram, selector, rangeInterval, { le: '+Inf' }, aggregationFunction='sum', aggregationLabels=[aggregationLabel]),
    numeratorQuery: generateApdexNumeratorQuery(histogram, selector, rangeInterval, aggregationFunction='sum', aggregationLabels=[aggregationLabel]),
    aggregationLabel: aggregationLabel,
    aggregatedTotalQuery: generateApdexComponentRateQuery(histogram, selector, rangeInterval, { le: '+Inf' }, aggregationFunction='sum', aggregationLabels=[]),
  };

{
  histogramApdex(
    histogram,
    selector='',
    satisfiedThreshold=null,
    toleratedThreshold=null
  ):: {
    histogram: histogram,
    selector: selector,
    satisfiedThreshold: satisfiedThreshold,
    toleratedThreshold: toleratedThreshold,

    apdexQuery(aggregationLabels, selector, rangeInterval)::
      generateApdexScoreQuery(
        self,
        aggregationLabels,
        selector,
        rangeInterval,
        aggregationFunction='sum'
      ),

    /* apdexSuccessRateQuery measures the rate at which apdex violations occur */
    apdexSuccessRateQuery(aggregationLabels, selector, rangeInterval)::
      generateApdexNumeratorQuery(self, selector, rangeInterval, aggregationFunction='sum', aggregationLabels=aggregationLabels),

    apdexWeightQuery(aggregationLabels, selector, rangeInterval)::
      generateApdexComponentRateQuery(self, selector, rangeInterval, { le: '+Inf' }, aggregationFunction='sum', aggregationLabels=aggregationLabels),

    percentileLatencyQuery(percentile, aggregationLabels, selector, rangeInterval)::
      generatePercentileLatencyQuery(self, percentile, aggregationLabels, selector, rangeInterval),

    // This is used to combine multiple apdex scores for a combined percentileLatencyQuery
    aggregatedRateQuery(aggregationLabels, selector, rangeInterval)::
      generateApdexComponentRateQuery(self, selector, rangeInterval, aggregationFunction='sum', aggregationLabels=aggregationLabels),

    describe()::
      local s = self;
      // TODO: don't assume the metric is in seconds!
      if s.toleratedThreshold == null then
        '%gs' % [s.satisfiedThreshold]
      else
        '%gs/%gs' % [s.satisfiedThreshold, s.toleratedThreshold],

    // The preaggregated numerator expression
    // used for combinations
    apdexNumerator(selector, rangeInterval, histogramRates=false)::
      generateApdexNumeratorQuery(self, selector, rangeInterval, aggregationFunction=null, aggregationLabels=[], histogramRates=histogramRates),

    // The preaggregated denominator expression
    // used for combinations
    apdexDenominator(selector, rangeInterval)::
      generateApdexComponentRateQuery(self, selector, rangeInterval, { le: '+Inf' }, aggregationFunction=null, aggregationLabels=[]),

    apdexAttribution(aggregationLabel, selector, rangeInterval)::
      generateApdexAttributionQuery(self, selector, rangeInterval, aggregationLabel=aggregationLabel),

    // Only support reflection on hash selectors
    [if std.isObject(selector) then 'supportsReflection']():: {
      // Returns a list of metrics and the labels that they use
      getMetricNamesAndLabels()::
        {
          [histogram]: std.set(std.objectFields(selector) + ['le']),
        },
    },
  },
}
