// This file is autogenerated using scripts/generate-service-dashboards
// Please feel free to customize this file.
local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local serviceDashboard = import 'gitlab-dashboards/service_dashboard.libsonnet';

serviceDashboard.overview(
  'runway',
  includeStandardEnvironmentAnnotations=false,
)
.addAnnotation(
    grafana.annotation.datasource(
      'runway-deploy',
      '-- Grafana --',
      iconColor='#fda324',
      tags=['platform:runway', 'env:${environment}'],
      builtIn=1,
    ),
)
.overviewTrailer()
