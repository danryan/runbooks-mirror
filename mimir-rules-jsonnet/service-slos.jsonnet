local separateMimirRecordingFiles = (import 'recording-rules/lib/mimir/separate-mimir-recording-files.libsonnet').separateMimirRecordingFiles;
local serviceSlosRules = import 'recording-rules/service-slos.libsonnet';
local services = (import 'gitlab-metrics-config.libsonnet').monitoredServices;

local outputPromYaml(groups) =
  std.manifestYamlDoc({
    groups: groups,
  });

local rulesWithThanosRulerLabelForService(service) =
  local rules = serviceSlosRules.rules([service], allServices=[service]);
  std.map(
    function(rule)
      rule {
        // temporary solution until we move away from Thanos Ruler completely
        // https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/2902
        labels+: { monitor: 'global' },
      },
    rules
  );

local fileForService(service, selector, _extraArgs) =
  {
    ['%s-service-slos' % service.type]: outputPromYaml([{
      name: 'Autogenerated Service SLOs',
      interval: '5m',
      rules: rulesWithThanosRulerLabelForService(service),
    }]),
  };

std.foldl(
  function(memo, service)
    memo + separateMimirRecordingFiles(
      fileForService,
      service,
    ),
  services,
  {}
)