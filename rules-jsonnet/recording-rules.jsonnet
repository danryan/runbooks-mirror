local configMap = import './lib/recording-rules/config-map.libsonnet';
local services = import './services/all.jsonnet';

local outputPromYaml(groups) =
  std.manifestYamlDoc({
    groups: groups,
  });

// Select all services with `autogenerateRecordingRules` (default on)
local selectedServices = std.filter(function(service) service.autogenerateRecordingRules, services);

{
  ['key-metrics-%s.yml' % [service.type]]:
    outputPromYaml(
      configMap.prometheus.recordingRuleGroupsForService(service)
    )
  for service in services
}
