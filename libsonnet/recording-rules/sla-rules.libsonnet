local availabilityPromql = import 'gitlab-availability/availability-promql.libsonnet';
local metricsConfig = import 'gitlab-metrics-config.libsonnet';
local selectors = import 'promql/selectors.libsonnet';
local serviceCatalog = import 'service-catalog/service-catalog.libsonnet';

local keyServiceWeights = std.foldl(
  function(memo, item) memo {
    [item.name]: item.business.SLA.overall_sla_weighting,
  }, serviceCatalog.findKeyBusinessServices(), {}
);

// This allows overriding values stored in the service catalog as well as adding services and
// their weight.
local keyServiceWeightsMapping = {
  'weighted_v2.1': keyServiceWeights,
  weighted_v3: keyServiceWeights { sidekiq: 1 },
};

// This allows changing the interval we average over for the SLA
local weightedIntervalVersions = {
  'weighted_v2.1': '5m',
  weighted_v3: '5m',
};

assert std.set(std.objectFields(keyServiceWeightsMapping)) == std.set(std.objectFields(weightedIntervalVersions)) : 'All versions in `keyServiceWeightMapping` need to be in `weightedIntervalVersions`';

local getScoreQuery(weights, interval, selector, sloObservationStatusMetric) =
  local items = [
    'min without(slo) (avg_over_time(%(sloObservationStatusMetric)s{%(selector)s}[%(interval)s])) * %(weight)d' % {
      selector: selectors.serializeHash({ type: type, monitor: 'global' } + selector),
      weight: weights[type],
      interval: interval,
      sloObservationStatusMetric: sloObservationStatusMetric,
    }
    for type in std.objectFields(weights)
  ];

  std.join('\n  or\n  ', items);

local getWeightQuery(weights, interval, selector, sloObservationStatusMetric) =
  local items = [
    'group without(slo) (avg_over_time(%(sloObservationStatusMetric)s{%(selector)s}[%(interval)s])) * %(weight)d' % {
      selector: selectors.serializeHash({ type: type, monitor: 'global' } + selector),
      weight: weights[type],
      interval: interval,
      sloObservationStatusMetric: sloObservationStatusMetric,
    }
    for type in std.objectFields(weights)
  ];

  std.join('\n  or\n  ', items);

local ruleGroup(version, selector, sloObservationStatusMetric) =
  local labels = {
    sla_type: version,
  };
  local interval = weightedIntervalVersions[version];
  local serviceWeights = keyServiceWeightsMapping[version];

  {
    name: 'SLA weight calculations - %s' % [version],
    interval: '1m',
    rules: [{
      // TODO: these are kept for backwards compatability for now
      record: 'sla:gitlab:score',
      labels: labels,
      expr: |||
        sum by (environment, env, stage) (
          %s
        )
      ||| % [getScoreQuery(serviceWeights, interval, selector, sloObservationStatusMetric)],
    }, {
      // TODO: these are kept for backwards compatibility for now
      // See https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/309
      record: 'sla:gitlab:weights',
      labels: labels,
      expr: |||
        sum by (environment, env, stage) (
          %s
        )
      ||| % [getWeightQuery(serviceWeights, interval, selector, sloObservationStatusMetric)],
    }, {
      record: 'sla:gitlab:ratio',
      labels: labels,
      // Adding a clamp here is a safety precaution. In normal circumstances this should
      // never exceed one. However in incidents such as show,
      // https://gitlab.com/gitlab-com/gl-infra/reliability/-/issues/11457
      // there are failure modes where this may occur.
      // Having the clamp_max guard clause can help contain the blast radius.
      expr: |||
        clamp_max(
          sla:gitlab:score{%(selectors)s} / sla:gitlab:weights{%(selectors)s},
          1
        ) unless on () max(gitlab_maintenance_mode{%(environment)s} == 1)
      ||| % {
        selectors: selectors.serializeHash(labels { monitor: 'global' } + selector),
        environment: selectors.serializeHash(selector),
      },
    }],
  };

local occurenceRatesRuleGroup(selector) = {
  name: 'Autogenerated Availability Rates',
  interval: '5m',
  rules: availabilityPromql.new(
    metricsConfig.keyServices,
    metricsConfig.aggregationSets.serviceSLIs,
    extraSelector=selector,
  ).rateRules,
};

local slaRules(selector, sloObservationStatusMetric, groupExtras={}) = {
  groups: [
            ruleGroup(version, selector, sloObservationStatusMetric) + groupExtras
            for version in std.objectFields(weightedIntervalVersions)
          ]
          +
          [occurenceRatesRuleGroup(selector) + groupExtras],
};

local slaTargetRules(groupExtras={}) = {
  groups: [{
    name: 'SLA target',
    interval: '5m',
    rules: [{
      record: 'sla:gitlab:target',
      expr: '%g' % [metricsConfig.slaTarget],
    }],
  } + groupExtras],
};

{
  slaRules:: slaRules,
  slaTargetRules:: slaTargetRules,
}
