// This file is autogenerated using scripts/generate-service-dashboards
// Please feel free to customize this file.
local serviceDashboard = import 'gitlab-dashboards/service_dashboard.libsonnet';

// The default environment selector includes
// environment=, but we specifically don't want to
// target any single environment for thanos,
// viewing data across all environments instead.
local environmentSelector = {};

serviceDashboard.overview(
  'thanos',
  environmentSelectorHash=environmentSelector,
)
.overviewTrailer()