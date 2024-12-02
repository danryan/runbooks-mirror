local sliDefinition = import './service_level_indicator_definition.libsonnet';
local sliMetricsDescriptor = import './sli_metric_descriptor.libsonnet';
local collectMetricNamesAndSelectors = sliMetricsDescriptor.collectMetricNamesAndSelectors;
local test = import 'test.libsonnet';
local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local successCounterApdex = metricsCatalog.successCounterApdex;
local errorCounterApdex = metricsCatalog.errorCounterApdex;
local combined = metricsCatalog.combined;
local rateMetric = metricsCatalog.rateMetric;
local derivMetric = metricsCatalog.derivMetric;
local gaugeMetric = metricsCatalog.gaugeMetric;
local combinedSli = import './combined_service_level_indicator_definition.libsonnet';

test.suite({
  testCollectMetricNamesAndSelectorsEmptyArray: {
    actual: collectMetricNamesAndSelectors([]),
    expect: {},
  },
  testCollectMetricNamesAndSelectorsArrayOfEmptyHashes: {
    actual: collectMetricNamesAndSelectors([{}, {}, {}]),
    expect: {},
  },
  testCollectMetricNamesAndSelectorsDifferentLabels: {
    actual: collectMetricNamesAndSelectors([
      { metric_foo: { type: 'foo' } },
      { metric_bar: { job: 'bar' } },
    ]),
    expect: {
      metric_foo: { type: { oneOf: ['foo'] } },
      metric_bar: { job: { oneOf: ['bar'] } },
    },
  },
  testCollectMetricNamesAndSelectorsSameLabels: {
    actual: collectMetricNamesAndSelectors([
      { metric_foo: { type: 'foo' } },
      { metric_foo: { type: 'bar' } },
    ]),
    expect: {
      metric_foo: { type: { oneOf: ['bar', 'foo'] } },
    },
  },
  testCollectMetricNamesAndSelectorsMultipleHashes: {
    actual: collectMetricNamesAndSelectors([
      { metric_foo: { type: 'foo', job: 'bar' } },
      { metric_foo: { type: 'foo', job: 'baz' } },
      { metric_boo: { type: 'boo' } },
      { metric_boo: { job: 'boo' } },
    ]),
    expect: {
      metric_foo: { type: { oneOf: ['foo'] }, job: { oneOf: ['bar', 'baz'] } },
      metric_boo: {},
    },
  },
  testCollectMetricNamesAndSelectorsNestedSelector1: {
    actual: collectMetricNamesAndSelectors([
      { metric_foo: { code: { re: '^5.*' } } },
      { metric_foo: { code: { re: '^4.*' } } },
    ]),
    expect: { metric_foo: { code: { oneOf: ['^4.*', '^5.*'] } } },
  },
  testCollectMetricNamesAndSelectorsNestedSelector2: {
    actual: collectMetricNamesAndSelectors([
      { metric_foo: { code: { re: '^5.*' }, type: 'foo' } },
      { metric_foo: { code: { re: '^4.*' }, type: 'bar' } },
    ]),
    expect: {
      metric_foo: {
        code: { oneOf: ['^4.*', '^5.*'] },
        type: { oneOf: ['bar', 'foo'] },
      },
    },
  },
  testCollectMetricNamesAndSelectorsNestedSelector3: {
    actual: collectMetricNamesAndSelectors([
      { metric_foo: { code: { re: '^4.*|^5.*', ne: '200' } } },
      { metric_foo: { code: { re: '^4.*', nre: '^2.*' } } },
    ]),
    expect: { metric_foo: { code: { oneOf: ['^4.*', '^4.*|^5.*'] } } },
  },
  testCollectMetricNamesAndSelectorsNestedSelector4: {
    actual: collectMetricNamesAndSelectors([
      { metric_foo: { backend: { oneOf: ['a', 'b'] } } },
      { metric_foo: { backend: { oneOf: ['c', 'd'] } } },
      { metric_foo: { backend: { oneOf: ['e', 'f'] } } },
    ]),
    expect: { metric_foo: { backend: { oneOf: ['a', 'b', 'c', 'd', 'e', 'f'] } } },
  },
  testCollectMetricNamesAndSelectorsNestedSelector5: {
    actual: collectMetricNamesAndSelectors(
      [
        { some_total: { backend: { oneOf: ['web'] }, code: { oneOf: ['5xx'] } } },
        { some_total: { backend: { oneOf: ['abc'] } } },
      ]
    ),
    expect: {
      some_total: {
        backend: { oneOf: ['abc', 'web'] },
      },
    },
  },
  testCollectMetricNamesAndSelectorsNestedSelector6: {
    actual: collectMetricNamesAndSelectors(
      [
        { some_total: { backend: { oneOf: ['web'] } } },
        { some_total: { backend: { oneOf: ['abc'] }, code: { oneOf: ['5xx'] } } },
      ]
    ),
    expect: {
      some_total: {
        backend: { oneOf: ['abc', 'web'] },
      },
    },
  },
  testCollectMetricNamesAndSelectorsNestedSelector7: {
    actual: collectMetricNamesAndSelectors(
      [
        { some_total: { backend: { oneOf: ['web'] } } },
        { some_total: { backend: {} } },
      ]
    ),
    expect: {
      some_total: {},
    },
  },
  testCollectMetricNamesAndSelectorsNestedSelector8: {
    actual: collectMetricNamesAndSelectors(
      [
        { some_total: { backend: { oneOf: ['web'] } } },
        { some_total: {} },
      ]
    ),
    expect: {
      some_total: {},
    },
  },

  testNormalizeSelectorHashEmpty: {
    actual: sliMetricsDescriptor._normalizeSelectorExpression({}),
    expect: {},
  },
  testNormalizeSelectorHash1: {
    actual: sliMetricsDescriptor._normalizeSelectorExpression({ eq: 'a' }),
    expect: { oneOf: ['a'] },
  },
  testNormalizeSelectorHash2: {
    actual: sliMetricsDescriptor._normalizeSelectorExpression({ re: 'a' }),
    expect: { oneOf: ['a'] },
  },
  testNormalizeSelectorHash3: {
    actual: sliMetricsDescriptor._normalizeSelectorExpression({ re: 'a|b' }),
    expect: { oneOf: ['a|b'] },
  },
  testNormalizeSelectorHash4: {
    actual: sliMetricsDescriptor._normalizeSelectorExpression({ oneOf: ['a'] }),
    expect: { oneOf: ['a'] },
  },
  testNormalizeSelectorHash5: {
    actual: sliMetricsDescriptor._normalizeSelectorExpression({ ne: 'a' }),
    expect: {},
  },
  testNormalizeSelectorHash6: {
    actual: sliMetricsDescriptor._normalizeSelectorExpression({ nre: 'a|b' }),
    expect: {},
  },
  testNormalizeSelectorHash7: {
    actual: sliMetricsDescriptor._normalizeSelectorExpression({ noneOf: ['a', 'b'] }),
    expect: {},
  },
  testNormalizeSelectorHash8: {
    actual: sliMetricsDescriptor._normalizeSelectorExpression({ eq: 'a', re: 'b' }),
    expect: { oneOf: ['a', 'b'] },
  },
  testNormalizeSelectorHash9: {
    actual: sliMetricsDescriptor._normalizeSelectorExpression({ eq: 'a', re: 'a|b|c' }),
    expect: { oneOf: ['a', 'a|b|c'] },
  },
  testNormalizeSelectorHash10: {
    actual: sliMetricsDescriptor._normalizeSelectorExpression({ eq: 'a', oneOf: ['a', 'b', 'c'] }),
    expect: { oneOf: ['a', 'b', 'c'] },
  },
  testNormalizeSelectorHash11: {
    actual: sliMetricsDescriptor._normalizeSelectorExpression({ re: 'a|d|e|f', oneOf: ['a', 'b', 'c'] }),
    expect: { oneOf: ['a', 'a|d|e|f', 'b', 'c'] },
  },
  testNormalizeSimpleStr: {
    actual: sliMetricsDescriptor._normalize({ a: '1' }),
    expect: { a: { oneOf: ['1'] } },
  },
  testNormalizeSimpleInt: {
    actual: sliMetricsDescriptor._normalize({ a: 1 }),
    expect: { a: { oneOf: ['1'] } },
  },
  testNormalizeObject1: {
    actual: sliMetricsDescriptor._normalize({ a: { eq: '1' } }),
    expect: { a: { oneOf: ['1'] } },
  },
  testNormalizeObject2: {
    actual: sliMetricsDescriptor._normalize({ a: { eq: '1', re: '2' } }),
    expect: { a: { oneOf: ['1', '2'] } },
  },
  testNormalizeObject3: {
    actual: sliMetricsDescriptor._normalize({ a: [{ eq: '1' }, { re: '2' }] }),
    expect: { a: { oneOf: ['1', '2'] } },
  },
  testNormalizeObjectMultipleKeys: {
    actual: sliMetricsDescriptor._normalize({ a: '1', b: '2' }),
    expect: { a: { oneOf: ['1'] }, b: { oneOf: ['2'] } },
  },
  testNormalizeObjectWithNegativeExp: {
    actual: sliMetricsDescriptor._normalize({ a: { ne: '1', nre: '2|3' } }),
    expect: {},
  },
  testNormalizeObjectWithNegativeExp2: {
    actual: sliMetricsDescriptor._normalize({ a: { ne: '1', nre: '2|3', eq: '4', re: '1|2|5' } }),
    expect: { a: { oneOf: ['1|2|5', '4'] } },
  },
  testNormalizeObjectWithNegativeExp3: {
    actual: sliMetricsDescriptor._normalize({ a: [{ ne: '1' }, '2'] }),
    expect: { a: { oneOf: ['2'] } },
  },
  testNormalizeArray: {
    actual: sliMetricsDescriptor._normalize({ a: ['1', '2', '3'] }),
    expect: { a: { oneOf: ['1', '2', '3'] } },
  },
  testNormalizeEqArray: {
    actual: sliMetricsDescriptor._normalize({ a: { eq: ['1', '2', '3'] } }),
    expect: { a: { oneOf: ['1', '2', '3'] } },
  },
  testNormalizeReArray: {
    actual: sliMetricsDescriptor._normalize({ a: { re: ['1', '2', '3'] } }),
    expect: { a: { oneOf: ['1', '2', '3'] } },
  },
  testMergeSelector1: {
    actual: sliMetricsDescriptor._mergeSelector(
      { a: '1' },
      { a: '1' },
    ),
    expect: { a: { oneOf: ['1'] } },
  },
  testMergeSelector2: {
    actual: sliMetricsDescriptor._mergeSelector(
      { a: '1' },
      { a: '2' },
    ),
    expect: { a: { oneOf: ['1', '2'] } },
  },
  testMergeSelector3: {
    actual: sliMetricsDescriptor._mergeSelector(
      { a: { eq: '1', re: '2|3' } },
      { a: { eq: '4', oneOf: ['5', '6'] } },
    ),
    expect: { a: { oneOf: ['1', '2|3', '4', '5', '6'] } },
  },
  testMergeSelector4: {
    actual: sliMetricsDescriptor._mergeSelector(
      { a: [{ eq: '1' }, { re: '2|3' }] },
      { a: { eq: '4', oneOf: ['5', '6'] } },
    ),
    expect: { a: { oneOf: ['1', '2|3', '4', '5', '6'] } },
  },
  testMergeSelector5: {
    actual: sliMetricsDescriptor._mergeSelector(
      { a: '1', b: '10' },
      { a: { re: '2|3|4', ne: '2' }, b: { re: '11|12' } },
    ),
    expect: {
      a: { oneOf: ['1', '2|3|4'] },
      b: { oneOf: ['10', '11|12'] },
    },
  },
  testMergeSelector6: {
    actual: sliMetricsDescriptor._mergeSelector(
      { backend: { oneOf: ['web'] }, code: { oneOf: ['5xx'] } },
      { backend: { oneOf: ['abc'] } },
    ),
    expect: {
      backend: { oneOf: ['abc', 'web'] },
    },
  },
  testMergeSelector7: {
    actual: sliMetricsDescriptor._mergeSelector(
      { backend: { oneOf: ['web'] } },
      { backend: { oneOf: ['abc'] }, code: { oneOf: ['5xx'] } },
    ),
    expect: {
      backend: { oneOf: ['abc', 'web'] },
    },
  },
  testMergeSelector8: {
    actual: sliMetricsDescriptor._mergeSelector(
      { backend: {} },
      { backend: {} },
    ),
    expect: {},
  },
  testMergeSelector9: {
    actual: sliMetricsDescriptor._mergeSelector(
      { code: '500' },
      {},
    ),
    expect: {},
  },
  testMergeSelector10: {
    actual: sliMetricsDescriptor._mergeSelector(
      { type: { ne: 'abcd' } },
      { type: { ne: 'abcd' } },
    ),
    expect: {},
  },

  local testSliBase = {
    significantLabels: [],
    userImpacting: false,
  },

  local testMetricsDescriptorAggregationLabels(sliDefinitions, expect) = {
    local descriptor = sliMetricsDescriptor.sliMetricsDescriptor(sliDefinitions),
    actual: descriptor.aggregationLabelsByMetric,
    expect: expect,
  },
  local testMetricsDescriptorSelectors(sliDefinitions, expect) = {
    local descriptor = sliMetricsDescriptor.sliMetricsDescriptor(sliDefinitions),
    actual: descriptor.selectorsByMetric,
    expect: expect,
  },

  local testSLIs = {
    sliWithSelectorHistogramApdex: sliDefinition.serviceLevelIndicatorDefinition(testSliBase {
      apdex: histogramApdex('some_histogram_metrics', selector={ foo: 'bar' }),
      requestRate: rateMetric('some_total_count', selector={ label_a: 'bar' }),
      errorRate: rateMetric('some_total_count', selector={ label_b: 'foo' }),
    }).initServiceLevelIndicatorWithName('sliWithSelectorHistogramApdex', { type: 'fake_service' }),
    sliWithSelectorSuccessCounterApdex: sliDefinition.serviceLevelIndicatorDefinition(testSliBase {
      apdex: successCounterApdex(successRateMetric='success_total_count', operationRateMetric='some_total_count', selector={ foo: 'bar', baz: 'qux' }),
      requestRate: rateMetric('some_total_count', selector={ label_a: 'bar' }),
      errorRate: rateMetric('some_total_count', selector={ label_b: 'foo' }),
    }).initServiceLevelIndicatorWithName('sliWithSelectorErrorCounterApdex', { type: 'fake_service' }),
    sliWithSelectorErrorCounterApdex: sliDefinition.serviceLevelIndicatorDefinition(testSliBase {
      apdex: errorCounterApdex(errorRateMetric='error_total_count', operationRateMetric='some_total_count', selector={ foo: 'bar', baz: 'qux' }),
      requestRate: rateMetric('some_total_count', selector={ label_a: 'bar' }),
      errorRate: rateMetric('some_total_count', selector={ label_b: 'foo' }),
    }).initServiceLevelIndicatorWithName('sliWithSelectorErrorCounterApdex', { type: 'fake_service' }),
    sliWithSelectorRequestRateOnly: sliDefinition.serviceLevelIndicatorDefinition(testSliBase {
      requestRate: rateMetric('some_total_count', selector={ label_a: 'bar', type: 'fake_service' }),
    }).initServiceLevelIndicatorWithName('sliWithSelectorRequestRateOnly', { type: 'fake_service' }),
    sliWithoutSelector: sliDefinition.serviceLevelIndicatorDefinition(testSliBase {
      apdex: histogramApdex('some_histogram_metrics'),
      requestRate: rateMetric('some_total_count'),
      errorRate: rateMetric('some_total_count'),
    }).initServiceLevelIndicatorWithName('sliWithoutSelector', { type: 'fake_service' }),
    sliWithCombinedMetric: sliDefinition.serviceLevelIndicatorDefinition(testSliBase {
      apdex: histogramApdex('some_histogram_metrics'),
      requestRate: combined([
        rateMetric(
          counter='pg_stat_database_xact_commit',
          selector={ type: 'fake_service', tier: 'db' },
          filterExpr='and on (fqdn) (pg_replication_is_replica == 0)'
        ),
        rateMetric(
          counter='pg_stat_database_xact_rollback',
          selector={ type: 'fake_service', tier: 'db', some_label: 'true' },
          filterExpr='and on (fqdn) (pg_replication_is_replica == 0)'
        ),
      ]),
      errorRate: rateMetric('some_total_count'),
    }).initServiceLevelIndicatorWithName('sliWithCombinedMetric', { type: 'fake_service' }),
    sliWithDerivMetric: sliDefinition.serviceLevelIndicatorDefinition(testSliBase {
      requestRate: derivMetric('some_deriv_count', { type: 'fake_service', job: 'bar' }),
    }).initServiceLevelIndicatorWithName('sliWithDerivMetric', { type: 'fake_service' }),
    sliWithGaugeMetric: sliDefinition.serviceLevelIndicatorDefinition(testSliBase {
      requestRate: gaugeMetric('some_gauge', { type: 'fake_service', job: 'bar' }),
    }).initServiceLevelIndicatorWithName('sliWithGaugeMetric', { type: 'fake_service' }),
    sliWithMultipleSelectors: sliDefinition.serviceLevelIndicatorDefinition(testSliBase {
      requestRate: rateMetric('some_total_count', { type: 'fake_service', job: { re: 'hello|world' } }),
      errorRate: rateMetric('some_total_count', { type: 'fake_service', job: { eq: 'boo' } }),
    }).initServiceLevelIndicatorWithName('sliWithMultipleSelectors', { type: 'fake_service' }),
    sliWithSignificantLabels: sliDefinition.serviceLevelIndicatorDefinition(testSliBase {
      requestRate: rateMetric('some_total_count', { label: 'foo', job: { re: 'hello|world' } }),
      errorRate: rateMetric('some_total_count', { label: 'bar', job: { eq: 'boo' } }),
      significantLabels: ['fizz', 'buzz'],
    }).initServiceLevelIndicatorWithName('sliWithSignificantLabels', { type: 'fake_service' }),
    combinedSli: combinedSli.combinedServiceLevelIndicatorDefinition(
      userImpacting=false,
      featureCategory='not_owned',
      description='',
      components=[
        metricsCatalog.serviceLevelIndicatorDefinition({
          userImpacting: false,
          significantLabels: ['hello'],
          requestRate: rateMetric(
            counter='some_total',
            selector={ foo: 'bar', backend: 'web' }
          ),
          errorRate: rateMetric(
            counter='some_total',
            selector={ foo: 'bar', backend: 'web', code: '5xx' }
          ),
        }),
        metricsCatalog.serviceLevelIndicatorDefinition({
          userImpacting: false,
          significantLabels: ['world'],
          requestRate: rateMetric(
            counter='some_total',
            selector={ foo: 'bar', backend: 'abc', type: 'fake_service' }
          ),
          errorRate: rateMetric(
            counter='some_total',
            selector={ foo: 'bar', backend: 'abc', type: 'fake_service', code: '5xx' }
          ),
        }),
        metricsCatalog.serviceLevelIndicatorDefinition({
          userImpacting: false,
          significantLabels: [],
          requestRate: rateMetric(
            counter='some_other_total',
            selector={ foo: 'bar', backend: 'abc' }
          ),
          errorRate: rateMetric(
            counter='some_other_total',
            selector={ foo: 'bar', backend: 'abc', code: '5xx' }
          ),
        }),
      ],
    ).initServiceLevelIndicatorWithName('combinedSli', { type: 'fake_service' }),
    sliWithSelectorEscapedRegex: sliDefinition.serviceLevelIndicatorDefinition(testSliBase {
      requestRate: rateMetric('some_total_count', selector={ route: '^foo', job: { re: '\\^blabla' } }),
      errorRate: rateMetric('some_total_count', selector={ route: 'bar', job: { re: 'something.*' } }),
    }).initServiceLevelIndicatorWithName('sliWithSelectorEscapedRegex', { type: 'fake_service' }),
    sliWithSelectorEscapedRegex2: sliDefinition.serviceLevelIndicatorDefinition(testSliBase {
      requestRate: rateMetric('some_total_count', selector={ route: { eq: '^foo' } }),
      errorRate: rateMetric('some_total_count', selector={ route: 'bar' }),
    }).initServiceLevelIndicatorWithName('sliWithSelectorEscapedRegex2', { type: 'fake_service' }),
    sliWithNegativeSelectorsOnly: sliDefinition.serviceLevelIndicatorDefinition(testSliBase {
      apdex: histogramApdex(
        histogram='gitlab_cache_operation_duration_seconds_bucket',
        selector={
          type: { ne: 'ops-gitlab-net' },
        },
        satisfiedThreshold=0.1,
        toleratedThreshold=0.25
      ),
      requestRate: rateMetric(
        counter='gitlab_cache_operation_duration_seconds_count',
        selector={
          type: { ne: 'ops-gitlab-net' },
        },
      ),
    }).initServiceLevelIndicatorWithName('sliTest', { type: 'fake_service' }),
  },
  testMetricNamesAndLabelsHistogramApdex: testMetricsDescriptorAggregationLabels(
    [testSLIs.sliWithSelectorHistogramApdex],
    expect={
      some_histogram_metrics: std.set(['foo', 'le']),
      some_total_count: std.set(['label_a', 'label_b']),
    }
  ),
  testMetricNamesAndSelectorsHistogramApdex: testMetricsDescriptorSelectors(
    [testSLIs.sliWithSelectorHistogramApdex],
    expect={
      some_histogram_metrics: {
        foo: { oneOf: ['bar'] },
      },
      some_total_count: {},

    }
  ),

  testMetricNamesAndLabelsSuccessCounterApdex: testMetricsDescriptorAggregationLabels(
    [testSLIs.sliWithSelectorSuccessCounterApdex],
    expect={
      success_total_count: std.set(['foo', 'baz']),
      some_total_count: std.set(['label_a', 'label_b', 'foo', 'baz']),
    }
  ),
  testMetricNamesAndSelectorsSuccessCounterApdex: testMetricsDescriptorSelectors(
    [testSLIs.sliWithSelectorSuccessCounterApdex],
    expect={
      success_total_count: {
        foo: { oneOf: ['bar'] },
        baz: { oneOf: ['qux'] },
      },
      some_total_count: {},
    }
  ),

  testMetricNamesAndLabelsErrorCounterApdex: testMetricsDescriptorAggregationLabels(
    [testSLIs.sliWithSelectorErrorCounterApdex],
    expect={
      error_total_count: std.set(['foo', 'baz']),
      some_total_count: std.set(['label_a', 'label_b', 'foo', 'baz']),
    },
  ),
  testMetricNamesAndSelectorsErrorCounterApdex: testMetricsDescriptorSelectors(
    [testSLIs.sliWithSelectorErrorCounterApdex],
    expect={
      error_total_count: {
        foo: { oneOf: ['bar'] },
        baz: { oneOf: ['qux'] },
      },
      some_total_count: {},
    },
  ),

  testMetricNamesAndLabelsRequestRateOnly: testMetricsDescriptorAggregationLabels(
    [testSLIs.sliWithSelectorRequestRateOnly],
    expect={
      some_total_count: std.set(['label_a', 'type']),
    },
  ),
  testMetricNamesAndSelectorsRequestRateOnly: testMetricsDescriptorSelectors(
    [testSLIs.sliWithSelectorRequestRateOnly],
    expect={
      some_total_count: {
        label_a: { oneOf: ['bar'] },
        type: { oneOf: ['fake_service'] },
      },
    },
  ),

  testMetricNamesAndLabelsWithoutSelector: testMetricsDescriptorAggregationLabels(
    [testSLIs.sliWithoutSelector],
    expect={
      some_histogram_metrics: ['le'],
      some_total_count: [],
    },
  ),
  testMetricNamesAndSelectorsWithoutSelector: testMetricsDescriptorSelectors(
    [testSLIs.sliWithoutSelector],
    expect={
      some_histogram_metrics: {},
      some_total_count: {},
    },
  ),

  testMetricNamesAndLabelsWithCombinedMetric: testMetricsDescriptorAggregationLabels(
    [testSLIs.sliWithCombinedMetric],
    expect={
      some_histogram_metrics: ['le'],
      pg_stat_database_xact_commit: std.set(['type', 'tier']),
      pg_stat_database_xact_rollback: std.set(['type', 'tier', 'some_label']),
      some_total_count: [],
    },
  ),
  testMetricNamesAndSelectorsWithCombinedMetric: testMetricsDescriptorSelectors(
    [testSLIs.sliWithCombinedMetric],
    expect={
      pg_stat_database_xact_commit: { tier: { oneOf: ['db'] }, type: { oneOf: ['fake_service'] } },
      pg_stat_database_xact_rollback: { some_label: { oneOf: ['true'] }, tier: { oneOf: ['db'] }, type: { oneOf: ['fake_service'] } },
      some_histogram_metrics: {},
      some_total_count: {},
    },
  ),

  testMetricNamesAndLabelsDerivMetric: testMetricsDescriptorAggregationLabels(
    [testSLIs.sliWithDerivMetric],
    expect={
      some_deriv_count: ['job', 'type'],
    },
  ),
  testMetricNamesAndSelectorsDerivMetric: testMetricsDescriptorSelectors(
    [testSLIs.sliWithDerivMetric],
    expect={
      some_deriv_count: {
        type: { oneOf: ['fake_service'] },
        job: { oneOf: ['bar'] },
      },
    },
  ),

  testMetricNamesAndLabelsGaugeMetric: testMetricsDescriptorAggregationLabels(
    [testSLIs.sliWithGaugeMetric],
    expect={
      some_gauge: ['job', 'type'],
    },
  ),
  testMetricNamesAndSelectorsGaugeMetric: testMetricsDescriptorSelectors(
    [testSLIs.sliWithGaugeMetric],
    expect={
      some_gauge: {
        type: { oneOf: ['fake_service'] },
        job: { oneOf: ['bar'] },
      },
    },
  ),

  testMetricNamesAndLabelsMultipleSelectors: testMetricsDescriptorAggregationLabels(
    [testSLIs.sliWithMultipleSelectors],
    expect={
      some_total_count: ['job', 'type'],
    },
  ),
  testMetricNamesAndSelectorsMultipleSelectors: testMetricsDescriptorSelectors(
    [testSLIs.sliWithMultipleSelectors],
    expect={
      some_total_count: {
        type: { oneOf: ['fake_service'] },
        job: { oneOf: ['boo', 'hello|world'] },
      },
    },
  ),

  testMetricNamesAndLabelsSignificantLabels: testMetricsDescriptorAggregationLabels(
    [testSLIs.sliWithSignificantLabels],
    expect={
      some_total_count: std.set(['fizz', 'buzz', 'job', 'label']),
    }
  ),
  testMetricNamesAndSelectorsSignificantLabels: testMetricsDescriptorSelectors(
    [testSLIs.sliWithSignificantLabels],
    expect={
      some_total_count: {
        label: { oneOf: ['bar', 'foo'] },
        job: { oneOf: ['boo', 'hello|world'] },
      },
    },
  ),

  testMetricNamesAndLabelsCombinedSli: testMetricsDescriptorAggregationLabels(
    [testSLIs.combinedSli],
    expect={
      some_total: std.set(['foo', 'backend', 'code', 'type', 'hello', 'world']),
      some_other_total: std.set(['foo', 'backend', 'code', 'hello', 'world']),
    }
  ),
  testMetricNamesAndSelectorsCombinedSli: testMetricsDescriptorSelectors(
    [testSLIs.combinedSli],
    expect={
      some_total: {
        foo: { oneOf: ['bar'] },
        backend: { oneOf: ['abc', 'web'] },
      },
      some_other_total: {
        foo: { oneOf: ['bar'] },
        backend: { oneOf: ['abc'] },
      },
    },
  ),

  testMetricNamesAndSelectorsEscapedRegex: testMetricsDescriptorSelectors(
    [testSLIs.sliWithSelectorEscapedRegex],
    expect={
      some_total_count: {
        route: { oneOf: ['\\\\^foo', 'bar'] },
        job: { oneOf: ['\\^blabla', 'something.*'] },
      },
    }
  ),
  testMetricNamesAndSelectorsEscapedRegex2: testMetricsDescriptorSelectors(
    [testSLIs.sliWithSelectorEscapedRegex2],
    expect={
      some_total_count: {
        route: { oneOf: ['\\\\^foo', 'bar'] },
      },
    }
  ),

  testDescriptorMultipleSLIs: {
    actual: sliMetricsDescriptor.sliMetricsDescriptor(std.objectValues(testSLIs)),
    expect: {
      aggregationLabelsByMetric: {
        error_total_count: ['baz', 'foo'],
        gitlab_cache_operation_duration_seconds_bucket: ['le', 'type'],
        gitlab_cache_operation_duration_seconds_count: ['type'],
        pg_stat_database_xact_commit: ['tier', 'type'],
        pg_stat_database_xact_rollback: ['some_label', 'tier', 'type'],
        some_deriv_count: ['job', 'type'],
        some_gauge: ['job', 'type'],
        some_histogram_metrics: ['foo', 'le'],
        some_other_total: ['backend', 'code', 'foo', 'hello', 'world'],
        some_total: ['backend', 'code', 'foo', 'hello', 'type', 'world'],
        some_total_count: ['baz', 'buzz', 'fizz', 'foo', 'job', 'label', 'label_a', 'label_b', 'route', 'type'],
        success_total_count: ['baz', 'foo'],
      },
      allMetricGroups: {
        combinedSli: std.set(['some_other_total', 'some_total']),
        sliTest: std.set(['gitlab_cache_operation_duration_seconds_bucket', 'gitlab_cache_operation_duration_seconds_count']),
        sliWithCombinedMetric: std.set(['some_histogram_metrics', 'pg_stat_database_xact_commit', 'pg_stat_database_xact_rollback', 'some_total_count']),
        sliWithDerivMetric: std.set(['some_deriv_count']),
        sliWithGaugeMetric: std.set(['some_gauge']),
        sliWithSelectorErrorCounterApdex: std.set(['error_total_count', 'success_total_count']),
        // Not in this list because they are already part of the group through other SLIs
        // sliWithSelectorHistogramApdex: ['some_histogram_metrics', 'some_total_count'] same as `sliWithCombinedMetric-apdex` + `sliWithCombinedMetric-ops`
        // sliWithSelectorSuccessCounterApdex: ['success_total_count', 'some_total_count'] same as `sliWithSelectorErrorCounterApdex-apdex` + `sliWithCombinedMetric-ops`
        // sliWithSelectorRequestRateOnly: ['some_total_count'] in `sliWithCombinedMetric-ops`
        // sliWithoutSelector: ['some_histogram_metrics', 'some_total_count']
        // sliWithMultipleSelectors: ['some_total_count']
        // sliWithSignificantLabels: ['some_total_count']
        // sliWithSelectorEscapedRegex: ['some_total_count']
        // sliWithSelectorEscapedRegex2: ['some_total_count']
        // sliWithNegativeSelectorsOnly: ['gitlab_cache_operation_duration_seconds_bucket']
      },
      emittingTypesByMetric: {
        error_total_count: ['fake_service'],
        gitlab_cache_operation_duration_seconds_bucket: ['fake_service'],
        gitlab_cache_operation_duration_seconds_count: ['fake_service'],
        pg_stat_database_xact_commit: ['fake_service'],
        pg_stat_database_xact_rollback: ['fake_service'],
        some_deriv_count: ['fake_service'],
        some_gauge: ['fake_service'],
        some_histogram_metrics: ['fake_service'],
        some_other_total: ['fake_service'],
        some_total: ['fake_service'],
        some_total_count: ['fake_service'],
        success_total_count: ['fake_service'],
      },
      selectorsByMetric: {
        error_total_count: { baz: { oneOf: ['qux'] }, foo: { oneOf: ['bar'] } },
        gitlab_cache_operation_duration_seconds_bucket: {},
        gitlab_cache_operation_duration_seconds_count: {},
        pg_stat_database_xact_commit: { tier: { oneOf: ['db'] }, type: { oneOf: ['fake_service'] } },
        pg_stat_database_xact_rollback: { some_label: { oneOf: ['true'] }, tier: { oneOf: ['db'] }, type: { oneOf: ['fake_service'] } },
        some_deriv_count: { job: { oneOf: ['bar'] }, type: { oneOf: ['fake_service'] } },
        some_gauge: { job: { oneOf: ['bar'] }, type: { oneOf: ['fake_service'] } },
        some_histogram_metrics: {},
        some_other_total: { backend: { oneOf: ['abc'] }, foo: { oneOf: ['bar'] } },
        some_total: { backend: { oneOf: ['abc', 'web'] }, foo: { oneOf: ['bar'] } },
        some_total_count: {},
        success_total_count: { baz: { oneOf: ['qux'] }, foo: { oneOf: ['bar'] } },
      },
    },
  },

  testSelectorsByMetricNegativeSelectorsOnly: testMetricsDescriptorSelectors(
    [testSLIs.sliWithNegativeSelectorsOnly],
    expect={
      gitlab_cache_operation_duration_seconds_bucket: {},
      gitlab_cache_operation_duration_seconds_count: {},
    }
  ),
})
