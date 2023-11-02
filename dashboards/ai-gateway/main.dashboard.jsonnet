// This file is autogenerated using scripts/generate-service-dashboards
// Please feel free to customize this file.
local platformLinks = import 'gitlab-dashboards/platform_links.libsonnet';
local serviceDashboard = import 'gitlab-dashboards/service_dashboard.libsonnet';

serviceDashboard.overview('ai-gateway')
.overviewTrailer() + {
  links+: [
    platformLinks.dynamicLinks('Code Suggestions Dashboards', 'type:code_suggestions'),
    platformLinks.dynamicLinks('Runway Dashboards', 'type:runway'),
  ],
}
