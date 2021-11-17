local aggregations = import 'promql/aggregations.libsonnet';
local selectors = import 'promql/selectors.libsonnet';
local strings = import 'utils/strings.libsonnet';

// Expression for upscaling an ratio
local upscaleRatioPromExpression = |||
  sum by (%(targetAggregationLabels)s) (
    sum_over_time(%(numeratorMetricName)s{%(sourceSelectorWithExtras)s}[%(burnRate)s])%(aggregationFilterExpr)s
  )
  /
  sum by (%(targetAggregationLabels)s) (
    sum_over_time(%(denominatorMetricName)s{%(sourceSelectorWithExtras)s}[%(burnRate)s])%(aggregationFilterExpr)s
  )
|||;

// Expression for upscaling a rate
// Note that unlike the ratio, a rate can be safely upscaled using
// avg_over_time
local upscaleRatePromExpression = |||
  sum by (%(targetAggregationLabels)s) (
    avg_over_time(%(metricName)s{%(sourceSelectorWithExtras)s}[%(burnRate)s])%(aggregationFilterExpr)s
  )
|||;

local errorRateWithFallbackPromExpression(sourceSet, burnRate) = |||
  (%(errorRateMetricName)s{%(sourceSelector)s} or (0 * %(opsRateMetricName)s{%(sourceSelector)s}))
||| % {
  errorRateMetricName: sourceSet.getErrorRateMetricForBurnRate(burnRate, required=true),
  opsRateMetricName: sourceSet.getOpsRateMetricForBurnRate(burnRate, required=true),
  sourceSelector: selectors.serializeHash(sourceSet.selector),
};

local joinExpr(targetAggregationSet) =
  if !std.objectHas(targetAggregationSet, 'joinSource') then
    ''
  else
    local requiredLabelsFromJoin = targetAggregationSet.joinSource.labels + [targetAggregationSet.joinSource.on];
    ' * on(%(joinOn)s) group_left(%(labels)s) (group by (%(aggregatedLabels)s) (%(metric)s))' % {
      joinOn: aggregations.serialize(targetAggregationSet.joinSource.on),
      labels: aggregations.serialize(targetAggregationSet.joinSource.labels),
      aggregatedLabels: aggregations.serialize(requiredLabelsFromJoin),
      metric: targetAggregationSet.joinSource.metric,
    };

local aggregationFilterExpr(targetAggregationSet) =
  local aggregationFilter = targetAggregationSet.aggregationFilter;

  // For service level aggregations, we need to filter out any SLIs which we don't want to include
  // in the service level aggregation.
  // These are defined in the SLI with `aggregateToService:false`
  joinExpr(targetAggregationSet) + if aggregationFilter != null then
    ' and on(component, type) (gitlab_component_service:mapping{%(selector)s})' % {
      selector: selectors.serializeHash(targetAggregationSet.selector {
        [aggregationFilter + '_aggregation']: 'yes',
      }),
    }
  else
    '';

// Upscale a RATIO from source metrics to target at the given target burnRate
local upscaledRatioExpression(sourceAggregationSet, targetAggregationSet, burnRate, numeratorMetricName, denominatorMetricName, extraSelectors={}) =
  local sourceSelectorWithExtras = sourceAggregationSet.selector + extraSelectors;

  upscaleRatioPromExpression % {
    burnRate: burnRate,
    targetAggregationLabels: aggregations.serialize(targetAggregationSet.labels),
    numeratorMetricName: numeratorMetricName,
    denominatorMetricName: denominatorMetricName,
    sourceSelectorWithExtras: selectors.serializeHash(sourceSelectorWithExtras),
    aggregationFilterExpr: aggregationFilterExpr(targetAggregationSet),
  };

// Upscale a RATE from source metrics to target at the given target burnRate
local upscaledRateExpression(sourceAggregationSet, targetAggregationSet, burnRate, metricName, extraSelectors={}) =
  local sourceSelectorWithExtras = sourceAggregationSet.selector + extraSelectors;

  upscaleRatePromExpression % {
    burnRate: burnRate,
    targetAggregationLabels: aggregations.serialize(targetAggregationSet.labels),
    metricName: metricName,
    sourceSelectorWithExtras: selectors.serializeHash(sourceSelectorWithExtras),
    aggregationFilterExpr: aggregationFilterExpr(targetAggregationSet),
  };

// Upscale an apdex RATIO from source metrics to target at the given target burnRate
local upscaledApdexRatioExpression(sourceAggregationSet, targetAggregationSet, burnRate, extraSelectors={}) =
  upscaledRatioExpression(
    sourceAggregationSet,
    targetAggregationSet,
    burnRate,
    numeratorMetricName=sourceAggregationSet.getApdexSuccessRateMetricForBurnRate('1h', required=true),
    denominatorMetricName=sourceAggregationSet.getApdexWeightMetricForBurnRate('1h', required=true),
    extraSelectors=extraSelectors,
  );

// Upscale an error RATIO from source metrics to target at the given target burnRate
local upscaledErrorRatioExpression(sourceAggregationSet, targetAggregationSet, burnRate, extraSelectors={}) =
  upscaledRatioExpression(
    sourceAggregationSet,
    targetAggregationSet,
    burnRate,
    numeratorMetricName=sourceAggregationSet.getErrorRateMetricForBurnRate('1h', required=true),
    denominatorMetricName=sourceAggregationSet.getOpsRateMetricForBurnRate('1h', required=true),
    extraSelectors=extraSelectors,
  );

// Upscale an apdex success RATE from source metrics to target at the given target burnRate
local upscaledApdexSuccessRateExpression(sourceAggregationSet, targetAggregationSet, burnRate, extraSelectors={}) =
  upscaledRateExpression(
    sourceAggregationSet,
    targetAggregationSet,
    burnRate,
    metricName=sourceAggregationSet.getApdexSuccessRateMetricForBurnRate('1h', required=true),
    extraSelectors=extraSelectors
  );

// Upscale an apdex total (weight) RATE from source metrics to target at the given target burnRate
local upscaledApdexWeightExpression(sourceAggregationSet, targetAggregationSet, burnRate, extraSelectors={}) =
  upscaledRateExpression(
    sourceAggregationSet,
    targetAggregationSet,
    burnRate,
    metricName=sourceAggregationSet.getApdexWeightMetricForBurnRate('1h', required=true),
    extraSelectors=extraSelectors
  );

// Upscale an ops RATE from source metrics to target at the given target burnRate
local upscaledOpsRateExpression(sourceAggregationSet, targetAggregationSet, burnRate, extraSelectors={}) =
  upscaledRateExpression(
    sourceAggregationSet,
    targetAggregationSet,
    burnRate,
    metricName=sourceAggregationSet.getOpsRateMetricForBurnRate('1h', required=true),
    extraSelectors=extraSelectors
  );

// Upscale an error RATE from source metrics to target at the given target burnRate
local upscaledErrorRateExpression(sourceAggregationSet, targetAggregationSet, burnRate, extraSelectors={}) =
  upscaledRateExpression(
    sourceAggregationSet,
    targetAggregationSet,
    burnRate,
    metricName=sourceAggregationSet.getErrorRateMetricForBurnRate('1h', required=true),
    extraSelectors=extraSelectors
  );

local upscaledSuccessRateExpression(sourceAggregationSet, targetAggregationSet, burnRate, extraSelectors={}) =
  local sourceMetricName = sourceAggregationSet.getSuccessRateMetricForBurnRate('1h', required=false);
  if sourceMetricName != null then
    upscaledRateExpression(
      sourceAggregationSet,
      targetAggregationSet,
      burnRate,
      metricName=sourceMetricName,
      extraSelectors=extraSelectors
    )
  else
    local upscaledOpsRate = strings.chomp(upscaledRateExpression(
      sourceAggregationSet,
      targetAggregationSet,
      burnRate,
      metricName=sourceAggregationSet.getOpsRateMetricForBurnRate('1h', required=true),
      extraSelectors=extraSelectors,
    ));
    local upscaledErrorRate = strings.chomp(upscaledRateExpression(
      sourceAggregationSet,
      targetAggregationSet,
      burnRate,
      metricName=sourceAggregationSet.getErrorRateMetricForBurnRate('1h', required=true),
      extraSelectors=extraSelectors,
    ));
    |||
      %(upscaledOpsRate)s
      -
      (
        %(upscaledErrorRate)s or (
          0 * %(indentedUpscaledOpsRate)s
        )
      )
    ||| % {
      upscaledOpsRate: upscaledOpsRate,
      upscaledErrorRate: strings.chomp(strings.indent(upscaledErrorRate, 2)),
      indentedUpscaledOpsRate: strings.chomp(strings.indent(upscaledOpsRate, 4)),
    };

// Generates a transformation expression that either uses direct, upscaled or
// or combines both in cases where the source expression contains a mixture
local combineUpscaleAndDirectTransformationExpressions(upscaledExprType, upscaleExpressionFn, sourceAggregationSet, targetAggregationSet, burnRate, directExpr) =
  // For 6h burn rate, we'll use either a combination of upscaling and direct aggregation,
  // or, if the source aggregations, don't exist, only use the upscaled metric
  if burnRate == '6h' then
    local upscaledExpr = upscaleExpressionFn(sourceAggregationSet, targetAggregationSet, burnRate, extraSelectors={ upscale_source: 'yes' });

    if directExpr != null then
      |||
        (
          %(directExpr)s
        )
        or
        (
          %(upscaledExpr)s
        )
      ||| % {
        directExpr: strings.indent(directExpr, 2),
        upscaledExpr: strings.indent(upscaledExpr, 2),
      }
    else
      // If we there is no source burnRate, use only upscaling
      upscaleExpressionFn(sourceAggregationSet, targetAggregationSet, burnRate)

  else if burnRate == '3d' then
    // For 3d expressions, we always use upscaling
    upscaleExpressionFn(sourceAggregationSet, targetAggregationSet, burnRate)
  else
    // For other burn rates, the direct expression must be used, so if it doesn't exist
    // there is a problem
    if directExpr == null then
      error 'Unable to generate a transformation expression from %(id)s for %(upscaledExprType)s for burn rate %(burnRate)s. No direct transformation is possible since source does not contain the correct expressions.' % {
        id: targetAggregationSet.id,
        upscaledExprType: upscaledExprType,
        burnRate: burnRate,
      }
    else
      directExpr;

local curry(upscaledExprType, upscaleExpressionFn) =
  function(sourceAggregationSet, targetAggregationSet, burnRate, directExpr)
    combineUpscaleAndDirectTransformationExpressions(
      upscaledExprType,
      upscaleExpressionFn,
      sourceAggregationSet,
      targetAggregationSet,
      burnRate,
      directExpr
    );

{
  aggregationFilterExpr:: aggregationFilterExpr,
  errorRateWithFallbackPromExpression:: errorRateWithFallbackPromExpression,

  // These functions generate either a direct or a upscaled transformation, or a combined expression

  // Ratios
  combinedApdexRatioExpression: curry('apdexRatio', upscaledApdexRatioExpression),
  combinedErrorRatioExpression: curry('errorRatio', upscaledErrorRatioExpression),

  // Rates
  combinedApdexSuccessRateExpression: curry('apdexSuccessRate', upscaledApdexSuccessRateExpression),
  combinedApdexWeightExpression: curry('apdexWeight', upscaledApdexWeightExpression),
  combinedOpsRateExpression: curry('opsRate', upscaledOpsRateExpression),
  combinedErrorRateExpression: curry('errorRate', upscaledErrorRateExpression),
  combinedSuccessRateExpression: curry('successRate', upscaledSuccessRateExpression),
}
