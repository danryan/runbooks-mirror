local multiburn_factors = import './multiburn_factors.libsonnet';
local aggregations = import 'promql/aggregations.libsonnet';
local selectors = import 'promql/selectors.libsonnet';
local strings = import 'utils/strings.libsonnet';


local errorRateTermWithFixedThreshold(
  metric,
  metricSelectorHash,
  comparator,
  burnrate,
  thresholdSLOValue
      ) =  // For an error rate, this is usually close to 0
  |||
    %(metric)s{%(metricSelector)s}
    %(comparator)s (%(burnrate)g * %(thresholdSLOValue)f)
  ||| % {
    metric: metric,
    burnrate: burnrate,
    metricSelector: selectors.serializeHash(metricSelectorHash),
    thresholdSLOValue: thresholdSLOValue,
    comparator: comparator,
  };

local errorRateTermWithMetricSLO(
  metric,
  metricSelectorHash,
  comparator,
  burnrate,
  sloMetric,
  sloMetricSelectorHash,
  sloMetricAggregationLabels,
      ) =
  |||
    %(metric)s{%(metricSelector)s}
    %(comparator)s on(%(sloMetricAggregationLabels)s) group_left()
    (
      %(burnrate)g * (
        avg by (%(sloMetricAggregationLabels)s) (%(sloMetric)s{%(sloSelector)s})
      )
    )
  ||| % {
    metric: metric,
    burnrate: burnrate,
    metricSelector: selectors.serializeHash(metricSelectorHash),
    sloMetric: sloMetric,
    sloSelector: selectors.serializeHash(sloMetricSelectorHash),
    sloMetricAggregationLabels: aggregations.serialize(sloMetricAggregationLabels),
    comparator: comparator,
  };

local apdexRateTermWithFixedThreshold(
  metric,
  metricSelectorHash,
  comparator,
  burnrate,
  thresholdSLOValue
      ) =  // For an apdex this is usually close to 1
  |||
    %(metric)s{%(metricSelector)s}
    %(comparator)s (1 - %(burnrate)g * %(inverseThresholdSLOValue)f)
  ||| % {
    metric: metric,
    burnrate: burnrate,
    metricSelector: selectors.serializeHash(metricSelectorHash),
    comparator: comparator,
    inverseThresholdSLOValue: 1 - thresholdSLOValue,
  };


local apdexRateTermWithMetricSLO(
  metric,
  metricSelectorHash,
  comparator,
  burnrate,
  sloMetric,
  sloMetricSelectorHash,
  sloMetricAggregationLabels,
      ) =
  |||
    %(metric)s{%(metricSelector)s}
    %(comparator)s on(%(sloMetricAggregationLabels)s) group_left()
    (
      1 -
      (
        %(burnrate)g * (1 - avg by (%(sloMetricAggregationLabels)s) (%(sloMetric)s{%(sloSelector)s}))
      )
    )
  ||| % {
    metric: metric,
    burnrate: burnrate,
    metricSelector: selectors.serializeHash(metricSelectorHash),
    sloMetric: sloMetric,
    sloSelector: selectors.serializeHash(sloMetricSelectorHash),
    sloMetricAggregationLabels: aggregations.serialize(sloMetricAggregationLabels),
    comparator: comparator,
  };

local operationRateFilter(
  expression,
  operationRateMetric,
  operationRateAggregationLabels,
  operationRateSelectorHash,
  minimumOperationRateForMonitoring
      ) =
  if operationRateMetric == null then
    expression
  else
    if operationRateAggregationLabels == null then
      |||
        (
          %(expression)s
        )
        and
        (
          %(operationRateMetric)s{%(operationRateSelector)s} >= %(minimumOperationRateForMonitoring)g
        )
      ||| % {
        expression: strings.indent(expression, 2),
        operationRateMetric: operationRateMetric,
        minimumOperationRateForMonitoring: minimumOperationRateForMonitoring,
        operationRateSelector: selectors.serializeHash(operationRateSelectorHash),
      }
    else
      |||
        (
          %(expression)s
        )
        and on(%(operationRateAggregationLabels)s)
        (
          sum by(%(operationRateAggregationLabels)s) (%(operationRateMetric)s{%(operationRateSelector)s}) >= %(minimumOperationRateForMonitoring)g
        )
      ||| % {
        expression: strings.indent(expression, 2),
        operationRateMetric: operationRateMetric,
        minimumOperationRateForMonitoring: minimumOperationRateForMonitoring,
        operationRateSelector: selectors.serializeHash(operationRateSelectorHash),
        operationRateAggregationLabels: aggregations.serialize(operationRateAggregationLabels),
      };

{
  // Generates a multi-window, multi-burn-rate error expression
  multiburnRateErrorExpression(
    metric1h,  // 1h burn rate metric
    metric5m,  // 5m burn rate metric
    metric30m,  // 30m burn rate metric
    metric6h,  // 6h burn rate metric
    metricSelectorHash,  // Selectors for the error rate metrics
    sloMetric=null,  // SLO metric name
    sloMetricSelectorHash=null,  // Selectors for the slo metric
    sloMetricAggregationLabels=null,  // Labels to join the SLO metric to the error rate metrics with
    operationRateMetric=null,  // Optional: operation rate metric for minimum operation rate clause
    operationRateAggregationLabels=null,  // Labels to aggregate the operation rate on, if any
    operationRateSelectorHash=null,  // Selector for the operation rate metric
    minimumOperationRateForMonitoring=null,  // minium operation rate vaue (in request-per-second)
    thresholdSLOValue=null,  // Error budget float value (between 0 and 1)
  )::
    local term(metric, burnrate) =
      if sloMetric != null then
        errorRateTermWithMetricSLO(
          metric=metric,
          metricSelectorHash=metricSelectorHash,
          comparator='>',
          burnrate=burnrate,
          sloMetric=sloMetric,
          sloMetricSelectorHash=sloMetricSelectorHash,
          sloMetricAggregationLabels=sloMetricAggregationLabels,
        )
      else
        errorRateTermWithFixedThreshold(
          metric=metric,
          metricSelectorHash=metricSelectorHash,
          comparator='>',
          burnrate=burnrate,
          thresholdSLOValue=thresholdSLOValue
        );

    local term_1h = term(metric1h, multiburn_factors.burnrate_1h);
    local term_5m = term(metric5m, multiburn_factors.burnrate_1h);
    local term_6h = term(metric6h, multiburn_factors.burnrate_6h);
    local term_30m = term(metric30m, multiburn_factors.burnrate_6h);

    local preOperationRateExpr = |||
      (
        %(term_1h)s
      )
      and
      (
        %(term_5m)s
      )
      or
      (
        %(term_6h)s
      )
      and
      (
        %(term_30m)s
      )
    ||| % {
      term_1h: strings.indent(term_1h, 2),
      term_5m: strings.indent(term_5m, 2),
      term_6h: strings.indent(term_6h, 2),
      term_30m: strings.indent(term_30m, 2),
    };

    operationRateFilter(
      preOperationRateExpr,
      operationRateMetric,
      operationRateAggregationLabels,
      operationRateSelectorHash,
      minimumOperationRateForMonitoring
    ),

  // Generates a multi-window, multi-burn-rate apdex score expression
  multiburnRateApdexExpression(
    metric1h,  // 1h burn rate metric
    metric5m,  // 5m burn rate metric
    metric30m,  // 30m burn rate metric
    metric6h,  // 6h burn rate metric
    metricSelectorHash,  // Selectors for the error rate metrics
    sloMetric=null,  // SLO metric name
    sloMetricSelectorHash=null,  // Selectors for the slo metric
    sloMetricAggregationLabels=null,  // Labels to join the SLO metric to the error rate metrics with
    operationRateMetric=null,  // Optional: operation rate metric for minimum operation rate clause
    operationRateAggregationLabels=null,  // Labels to aggregate the operation rate on, if any
    operationRateSelectorHash=null,  // Selector for the operation rate metric
    minimumOperationRateForMonitoring=null,  // minium operation rate vaue (in request-per-second)
    thresholdSLOValue=null  // Error budget float value (between 0 and 1)
  )::
    local term(metric, burnrate) =
      if sloMetric != null then
        apdexRateTermWithMetricSLO(
          metric=metric,
          metricSelectorHash=metricSelectorHash,
          comparator='<',
          burnrate=burnrate,
          sloMetric=sloMetric,
          sloMetricSelectorHash=sloMetricSelectorHash,
          sloMetricAggregationLabels=sloMetricAggregationLabels,
        )
      else
        apdexRateTermWithFixedThreshold(
          metric=metric,
          metricSelectorHash=metricSelectorHash,
          comparator='<',
          burnrate=burnrate,
          thresholdSLOValue=thresholdSLOValue,
        );

    local term_1h = term(metric1h, multiburn_factors.burnrate_1h);
    local term_5m = term(metric5m, multiburn_factors.burnrate_1h);
    local term_6h = term(metric6h, multiburn_factors.burnrate_6h);
    local term_30m = term(metric30m, multiburn_factors.burnrate_6h);

    local preOperationRateExpr = |||
      (
        %(term_1h)s
      )
      and
      (
        %(term_5m)s
      )
      or
      (
        %(term_6h)s
      )
      and
      (
        %(term_30m)s
      )
    ||| % {
      term_1h: strings.indent(term_1h, 2),
      term_5m: strings.indent(term_5m, 2),
      term_6h: strings.indent(term_6h, 2),
      term_30m: strings.indent(term_30m, 2),
    };

    operationRateFilter(
      preOperationRateExpr,
      operationRateMetric,
      operationRateAggregationLabels,
      operationRateSelectorHash,
      minimumOperationRateForMonitoring
    ),

  errorHealthExpression(
    metric1h,  // 1h burn rate metric
    metric5m,  // 5m burn rate metric
    metric30m,  // 30m burn rate metric
    metric6h,  // 6h burn rate metric
    metricSelectorHash,  // Selectors for the error rate metrics
    sloMetric,  // SLO metric name
    sloMetricSelectorHash,  // Selectors for the slo metric
    sloMetricAggregationLabels,  // Labels to join the SLO metric to the error rate metrics with
  )::
    local term(metric, burnrate) =
      errorRateTermWithMetricSLO(
        metric=metric,
        metricSelectorHash=metricSelectorHash,
        comparator='> bool',
        burnrate=burnrate,
        sloMetric=sloMetric,
        sloMetricSelectorHash=sloMetricSelectorHash,
        sloMetricAggregationLabels=sloMetricAggregationLabels,
      );

    local term_1h = term(metric1h, multiburn_factors.burnrate_1h);
    local term_5m = term(metric5m, multiburn_factors.burnrate_1h);
    local term_6h = term(metric6h, multiburn_factors.burnrate_6h);
    local term_30m = term(metric30m, multiburn_factors.burnrate_6h);

    // Prometheus doesn't have boolean AND/OR/NOT operators, only vector label matching versions of these operators.
    // As a cheap trick workaround, we substitute * with `boolean and` and `clamp_max(.. + .., 1) for  `boolean or`.
    // Why this works: Assuming x,y are both either 1 or 0.
    // * `x AND y` is equivalent to `x * y`
    // * `x OR y` is equivalent to `clamp_max(x + y, 1)`
    // * `NOT x` is equivalent to `x == bool 0`
    |||
      clamp_max(
        (
          %(term_1h)s
        )
        *
        (
          %(term_5m)s
        )
        +
        (
          %(term_6h)s
        )
        *
        (
          %(term_30m)s
        ),
        1
      ) == bool 0
    ||| % {
      term_1h: strings.indent(term_1h, 4),
      term_5m: strings.indent(term_5m, 4),
      term_6h: strings.indent(term_6h, 4),
      term_30m: strings.indent(term_30m, 4),
    },

  apdexHealthExpression(
    metric1h,  // 1h burn rate metric
    metric5m,  // 5m burn rate metric
    metric30m,  // 30m burn rate metric
    metric6h,  // 6h burn rate metric
    metricSelectorHash,  // Selectors for the error rate metrics
    sloMetric,  // SLO metric name
    sloMetricSelectorHash,  // Selectors for the slo metric
    sloMetricAggregationLabels,  // Labels to join the SLO metric to the error rate metrics with
  )::
    local term(metric, burnrate) =
      apdexRateTermWithMetricSLO(
        metric=metric,
        metricSelectorHash=metricSelectorHash,
        comparator='< bool',
        burnrate=burnrate,
        sloMetric=sloMetric,
        sloMetricSelectorHash=sloMetricSelectorHash,
        sloMetricAggregationLabels=sloMetricAggregationLabels,
      );

    local term_1h = term(metric1h, multiburn_factors.burnrate_1h);
    local term_5m = term(metric5m, multiburn_factors.burnrate_1h);
    local term_6h = term(metric6h, multiburn_factors.burnrate_6h);
    local term_30m = term(metric30m, multiburn_factors.burnrate_6h);

    // Prometheus doesn't have boolean AND/OR/NOT operators, only vector label matching versions of these operators.
    // As a cheap trick workaround, we substitute * with `boolean and` and `clamp_max(.. + .., 1) for  `boolean or`.
    // Why this works: Assuming x,y are both either 1 or 0.
    // * `x AND y` is equivalent to `x * y`
    // * `x OR y` is equivalent to `clamp_max(x + y, 1)`
    // * `NOT x` is equivalent to `x == bool 0`
    |||
      clamp_max(
        (
          %(term_1h)s
        )
        *
        (
          %(term_5m)s
        )
        +
        (
          %(term_6h)s
        )
        *
        (
          %(term_30m)s
        ),
        1
      ) == bool 0
    ||| % {
      term_1h: strings.indent(term_1h, 4),
      term_5m: strings.indent(term_5m, 4),
      term_6h: strings.indent(term_6h, 4),
      term_30m: strings.indent(term_30m, 4),
    },
}
