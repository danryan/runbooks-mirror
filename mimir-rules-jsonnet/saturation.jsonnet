local separateMimirRecordingFiles = (import 'recording-rules/lib/mimir/separate-mimir-recording-files.libsonnet').separateMimirRecordingFiles;
local saturationResources = import 'servicemetrics/saturation-resources.libsonnet';
local saturationRules = import 'servicemetrics/saturation_rules.libsonnet';
local monitoredServices = (import 'gitlab-metrics-config.libsonnet').monitoredServices;

local metricsAndServices = [
  [saturationMetric, service]
  for saturationMetric in std.objectFields(saturationResources)
  for service in saturationResources[saturationMetric].appliesTo
];

local resourcesByService = std.foldl(
  function(memo, tuple)
    local metricName = tuple[0];
    local serviceName = tuple[1];
    local service = std.get(memo, serviceName, {});
    memo {
      [serviceName]: service {
        [metricName]: saturationResources[metricName],
      },
    },
  metricsAndServices,
  {},
);

local filesForSeparateSelector(service, selector, _extraArgs) =
  local serviceResources = resourcesByService[service.type];
  local extraSourceSelector = selector { type: service.type };
  {
    saturation: std.manifestYamlDoc({
      groups:
        saturationRules.generateSaturationRulesGroup(
          saturationResources=serviceResources,
          extraSourceSelector=extraSourceSelector,
          evaluation='both',  // Drop this when migration to mimir is complete: https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/2815
        ),
    }),
    'saturation-alerts': std.manifestYamlDoc({
      groups:
        saturationRules.generateSaturationAuxRulesGroup(
          saturationResources=serviceResources,
          extraSelector=extraSourceSelector,
          evaluation='both',  // Drop this when migration to mimir is complete: https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/2815
        ),
    }),
    'saturation-metadata': std.manifestYamlDoc({
      groups:
        saturationRules.generateSaturationMetadataRulesGroup(
          saturationResources=serviceResources,
          evaluation='both',  // Drop this when migration to mimir is complete: https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/2815
          ignoreMetadata=true,  // Drop this when migration to mimir is complete: https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/2834
        ),
    }),
  };

std.foldl(
  function(memo, serviceName)
    local definitionsFound = std.filter(function(s) s.type == serviceName, monitoredServices);
    local fakeDefinition = { type: serviceName };
    local serviceDefinition = if std.length(definitionsFound) > 1
    then std.trace('More than one service definition found for ' + serviceName, fakeDefinition)
    else if std.length(definitionsFound) == 0
    then std.trace('No service definition found for ' + serviceName, fakeDefinition)
    else definitionsFound[0];
    memo + separateMimirRecordingFiles(filesForSeparateSelector, serviceDefinition),
  std.objectFields(resourcesByService),
  {}
)