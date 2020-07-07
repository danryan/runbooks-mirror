local configMap = import './lib/recording-rules/config-map.libsonnet';
local services = import './services/all.jsonnet';

local outputPromYaml(groups) =
  std.manifestYamlDoc({
    groups: groups,
  });

// Select all services with `autogenerateRecordingRules` (default on)
local selectedServices = std.filter(function(service) ({ autogenerateRecordingRules: true } + service).autogenerateRecordingRules, services);

{
  ['key-metrics-%s.yml' % [service.type]]:
    outputPromYaml(
      [{
        name: 'Autogenerated Component-Level SLIs: %s' % [service.type],
        interval: '1m',
        rules:
          configMap.prometheus.componentMetrics.generateRecordingRulesForService(service) +
          configMap.prometheus.extraRecordingRules.generateRecordingRulesForService(service),
      }]
      +
      (
        if ({ nodeLevelMonitoring: false } + service).nodeLevelMonitoring then
          [{
            name: 'Autogenerated Node-Level SLIs: %s' % [service.type],
            interval: '1m',
            rules: configMap.prometheus.nodeMetrics.generateRecordingRulesForService(service),
          }]
        else
          []
      )
      +
      [{
        name: 'Component mapping: %s' % [service.type],
        interval: '1m',  // TODO: we could probably extend this out to 5m
        rules: configMap.prometheus.componentMapping.generateRecordingRulesForService(service),
      }]
    )
  for service in services
}
