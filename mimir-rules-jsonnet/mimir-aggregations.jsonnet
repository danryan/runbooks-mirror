local separateMimirRecordingFiles = (import 'recording-rules/lib/mimir/separate-mimir-recording-files.libsonnet').separateMimirRecordingFiles;
local monitoredServices = (import 'gitlab-metrics-config.libsonnet').monitoredServices;
local recordingRules = import 'recording-rules/recording-rules.libsonnet';
local aggregationSets = (import 'gitlab-metrics-config.libsonnet').aggregationSets;
local intervalForDuration = import 'servicemetrics/interval-for-duration.libsonnet';
local recordingRuleRegistry = import 'servicemetrics/recording-rule-registry.libsonnet';

local outputPromYaml(groups) =
  std.manifestYamlDoc({ groups: groups });

local generatorsForService(aggregationSet, burnRate, extraSelector) = [
  recordingRules.componentMetricsRuleSetGenerator(
    burnRate=burnRate,
    aggregationSet=aggregationSet,
    extraSourceSelector=extraSelector,
    config={ recordingRuleRegistry: recordingRuleRegistry.unifiedRegistry },
  ),
];

local groupsForService(service, aggregationSet, extraSelector) =
  std.map(
    function(burnRate)
      local rules = std.flatMap(
        function(generator)
          generator.generateRecordingRulesForService(service),
        generatorsForService(aggregationSet, burnRate, extraSelector)
      );

      if std.length(rules) > 0 then
        {
          name: '%s: %s - Burn-Rate %s' % [aggregationSet.name, service.type, burnRate],
          interval: intervalForDuration.intervalForDuration(burnRate),
          rules: rules,
        }
      else {},
    aggregationSet.getBurnRates(),
  );

local aggregationsForService(service, selector, _extraArgs, _) =
  std.foldl(
    function(memo, set)
      local groups = std.prune(groupsForService(service, set, selector));
      if std.length(groups) > 0 then
        memo {
          ['%s-aggregation' % set.id]: outputPromYaml(groups),
        }
      else memo,
    aggregationSets.aggregationsFromSource,
    {}
  );

local servicesWithSlis = std.filter(function(service) std.length(service.listServiceLevelIndicators()) > 0, monitoredServices);
std.foldl(
  function(memo, service)
    memo + separateMimirRecordingFiles(
      aggregationsForService,
      service,
    ),
  servicesWithSlis,
  {}
)
