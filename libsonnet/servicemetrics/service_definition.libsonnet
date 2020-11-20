local serviceLevelIndicatorDefinition = import 'service_level_indicator_definition.libsonnet';

// For now we assume that services are provisioned on vms and not kubernetes
local provisioningDefaults = { vms: true, kubernetes: false };
local serviceDefaults = {
  autogenerateRecordingRules: true,
  disableOpsRatePrediction: false,
  nodeLevelMonitoring: false,  // By default we do not use node-level monitoring
};

// Convience method, will wrap a raw definition in a serviceLevelIndicatorDefinition if needed
local prepareComponent(definition) =
  if std.objectHasAll(definition, 'initServiceLevelIndicatorWithName') then
    // Already prepared
    definition
  else
    // Wrap class as a component definition
    serviceLevelIndicatorDefinition.serviceLevelIndicatorDefinition(definition);

local validateAndApplyServiceDefaults(service) =
  local serviceWithProvisioningDefaults = ({ provisioning: provisioningDefaults } + service);

  serviceDefaults + serviceWithProvisioningDefaults {
    serviceLevelIndicators: {
      [sliName]: prepareComponent(service.serviceLevelIndicators[sliName]).initServiceLevelIndicatorWithName(sliName)
      for sliName in std.objectFields(service.serviceLevelIndicators)
    },
  };

local serviceDefinition(service) =
  // Private functions
  local private = {
    serviceHasComponentWith(keymetricName)::
      std.foldl(
        function(memo, sliName) memo || std.objectHas(service.serviceLevelIndicators[sliName], keymetricName),
        std.objectFields(service.serviceLevelIndicators),
        false
      ),
  };

  service {
    hasApdex():: private.serviceHasComponentWith('apdex'),
    hasRequestRate():: true,  // requestRate is mandatory
    hasErrorRate():: private.serviceHasComponentWith('errorRate'),

    getProvisioning()::
      service.provisioning,

    // Returns an array of serviceLevelIndicators for this service
    listServiceLevelIndicators()::
      [
        service.serviceLevelIndicators[sliName]
        for sliName in std.objectFields(service.serviceLevelIndicators)
      ],
  };

{
  serviceDefinition(service)::
    serviceDefinition(validateAndApplyServiceDefaults(service)),
}
