local datasource = import 'grafonnet-dashboarding/gitlab-dashboards/datasource.libsonnet';
local commonAnnotations = import 'grafonnet-dashboarding/grafana/common_annotations.libsonnet';
local dashboard = import 'grafonnet-dashboarding/grafana/dashboard.libsonnet';
local g = import 'grafonnet-dashboarding/grafana/g.libsonnet';

local gitlabMetricsConfig = import 'gitlab-metrics-config.libsonnet';
local aggregationSets = gitlabMetricsConfig.aggregationSets;

local metricsCatalog = import 'servicemetrics/metrics-catalog.libsonnet';

local defaultEnvironmentSelector = gitlabMetricsConfig.grafanaEnvironmentSelector;


local overviewDashboard(
  type,
  title='Overview',
  uid=null,
  startRow=0,
  environmentSelectorHash=defaultEnvironmentSelector,
  saturationEnvironmentSelectorHash=defaultEnvironmentSelector,
  omitEnvironmentDropdown=false,
  includeStandardEnvironmentAnnotations=true,

  // Features
  showProvisioningDetails=true,
  showSystemDiagrams=true,
  expectMultipleSeries=false,
      ) =

  local metricsCatalogServiceInfo = metricsCatalog.getService(type);

  local stageLabels =
    if metricsCatalogServiceInfo.serviceIsStageless || !gitlabMetricsConfig.useEnvironmentStages then
      {}
    else
      { stage: '$stage' };

  local environmentStageSelectorHash = environmentSelectorHash + stageLabels;

  local extraAnnotations = if metricsCatalogServiceInfo.getProvisioning().runway then
    g.dashboard.withAnnotationsMixin(commonAnnotations.deploymentsForRunway(type))
  else {};

  local d =
    dashboard(
      title,
      uid=uid,
      tags=['gitlab', 'type:' + type, type, 'service overview'],
      includeStandardEnvironmentAnnotations=includeStandardEnvironmentAnnotations,
      includeEnvironmentTemplate=!omitEnvironmentDropdown && std.objectHas(environmentStageSelectorHash, 'environment'),
      defaultDatasource=datasource.defaultDatasourceForService(metricsCatalogServiceInfo)
    )
    + extraAnnotations;


  d {
    overviewTrailer()::
      self.trailer(),
  };

{
  overview:: overviewDashboard,
}
