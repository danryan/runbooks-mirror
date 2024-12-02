local sliDefinition = import './sli-definition.libsonnet';
local test = import 'test.libsonnet';
local objects = import 'utils/objects.libsonnet';

local validDefinition = {
  name: 'hello_sli',
  kinds: [sliDefinition.apdexKind],
  description: 'an SLI counting hellos',
  significantLabels: ['world'],
  featureCategory: 'error_budgets',
};

test.suite({
  testNew: {
    actual: sliDefinition.new(validDefinition),
    expectContains: {
      name: 'hello_sli',
      kinds: [sliDefinition.apdexKind],
      featureCategory: 'error_budgets',
      description: 'an SLI counting hellos',
      significantLabels: ['world'],
      totalCounterName: 'gitlab_sli_hello_sli_apdex_total',
      apdexTotalCounterName: 'gitlab_sli_hello_sli_apdex_total',
      apdexSuccessCounterName: 'gitlab_sli_hello_sli_apdex_success_total',
      recordingRuleMetrics: [
        'gitlab_sli_hello_sli_apdex_total',
        'gitlab_sli_hello_sli_apdex_success_total',
      ],
    },
  },

  testNewWithoutFeatureCategory: {
    local definitionWithoutFeatureCategory = objects.objectWithout(validDefinition, 'featureCategory') {
      significantLabels: ['world', 'feature_category'],
    },
    actual: sliDefinition.new(definitionWithoutFeatureCategory),
    expectContains: {
      featureCategory: 'featureCategoryFromSourceMetrics',
      significantLabels: ['world', 'feature_category'],
      recordingRuleStaticLabels: {},
    },
  },

  testNewWithFeatureCategory: {
    local definitionWithFeatureCategory = validDefinition {
      featureCategory: 'not_owned',
    },
    actual: sliDefinition.new(definitionWithFeatureCategory),
    expectContains: {
      featureCategory: 'not_owned',
      recordingRuleStaticLabels: { feature_category: 'not_owned' },
    },
  },

  testNewMultipleKinds: {
    actual: sliDefinition.new(validDefinition {
      kinds: [sliDefinition.apdexKind, sliDefinition.errorRateKind],
    }),
    expectContains: {
      kinds: [sliDefinition.apdexKind, sliDefinition.errorRateKind],
      totalCounterName: 'gitlab_sli_hello_sli_total',
      apdexTotalCounterName: 'gitlab_sli_hello_sli_apdex_total',
      apdexSuccessCounterName: 'gitlab_sli_hello_sli_apdex_success_total',
      errorTotalCounterName: 'gitlab_sli_hello_sli_total',
      errorCounterName: 'gitlab_sli_hello_sli_error_total',
      recordingRuleMetrics: [
        'gitlab_sli_hello_sli_apdex_total',
        'gitlab_sli_hello_sli_apdex_success_total',
        'gitlab_sli_hello_sli_total',
        'gitlab_sli_hello_sli_error_total',
      ],
    },
  },

  testInRecordingRuleRegistry: {
    local dummyRegistry = {
      resolveRecordingRuleFor(metricName=null, aggregationLabels=[], selector={}, rangeInterval='5m')::
        metricName == 'gitlab_sli_hello_sli_apdex_total',
    },
    actual: sliDefinition.new(validDefinition) { config+: { recordingRuleRegistry: dummyRegistry } }.inRecordingRuleRegistry(),
    expect: true,
  },

  local validSLI = sliDefinition._applyDefaults(validDefinition),

  testValdidateFeatureCategoryNotOwned: {
    local sli = validSLI { featureCategory: 'not_owned' },
    actual: sli,
    expectValid: sliDefinition._sliValidator,
  },


  testValidateFeatureCategoryUnknown: {
    local sli = validSLI { featureCategory: 'not a feature' },
    actual: sli,
    expectMatchingValidationError: {
      validator: sliDefinition._sliValidator,
      message: 'field featureCategory',
    },
  },

  testValidateFeatureCategoryNull: {
    local sli = validSLI { featureCategory: null },
    actual: sli,
    expectMatchingValidationError: {
      validator: sliDefinition._sliValidator,
      message: 'field featureCategory',
    },
  },

  testValidateFeatureCategoryMissing: {
    local sli = objects.objectWithout(validSLI, 'featureCategory'),
    actual: sli,
    expectMatchingValidationError: {
      validator: sliDefinition._sliValidator,
      message: 'field featureCategory',
    },
  },

  testValidateValidDashboardFeatureCategories: {
    local sli = validSLI { dashboardFeatureCategories: ['not_owned'] },
    actual: sli,
    expectValid: sliDefinition._sliValidator,
  },

  testValidateInvalidDashboardFeatureCategories: {
    local sli = validSLI { dashboardFeatureCategories: ['foo'] },
    actual: sli,
    expectMatchingValidationError: {
      validator: sliDefinition._sliValidator,
      message: 'field dashboardFeatureCategories',
    },
  },

  testValidateInvalidKind: {
    actual: validSLI { kinds: ['foo_rate'] },
    expectMatchingValidationError: {
      validator: sliDefinition._sliValidator,
      message: 'field kinds',
    },
  },

  testValidateNoKind: {
    actual: validSLI { kinds: [] },
    expectMatchingValidationError: {
      validator: sliDefinition._sliValidator,
      message: 'field kinds',
    },
  },

  local sliWithBothKinds = validDefinition { kinds+: [sliDefinition.errorRateKind] },
  testGenerateServiceLevelIndicator: {
    actual: sliDefinition.new(sliWithBothKinds).generateServiceLevelIndicator({}).hello_sli,
    expectContains: {
      requestRate: {
        counter: 'gitlab_sli_hello_sli_total',
        filterExpr: '',
        selector: {},
        metricNames: ['gitlab_sli_hello_sli_total'],
      },
      apdex: {
        operationRateMetric: 'gitlab_sli_hello_sli_apdex_total',
        selector: {},
        successRateMetric: 'gitlab_sli_hello_sli_apdex_success_total',
        metricNames: ['gitlab_sli_hello_sli_apdex_success_total', 'gitlab_sli_hello_sli_apdex_total'],
      },
      errorRate: {
        counter: 'gitlab_sli_hello_sli_error_total',
        filterExpr: '',
        selector: {},
        metricNames: ['gitlab_sli_hello_sli_error_total'],
      },
    },
  },
})
