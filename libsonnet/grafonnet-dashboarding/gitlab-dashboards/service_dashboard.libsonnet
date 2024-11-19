local datasource = import 'grafonnet-dashboarding/gitlab-dashboards/datasource.libsonnet';
local commonAnnotations = import 'grafonnet-dashboarding/grafana/common_annotations.libsonnet';
local dashboard = import 'grafonnet-dashboarding/grafana/dashboard.libsonnet';
local headlineMetricsRow = import 'grafonnet-dashboarding/panels/headline-metrics-row.libsonnet';

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
  local selectorHash = environmentStageSelectorHash { type: type };

  local d =
    dashboard(
      title,
      uid=uid,
      tags=['gitlab', 'type:' + type, type, 'service overview'],
      includeStandardEnvironmentAnnotations=includeStandardEnvironmentAnnotations,
      includeEnvironmentTemplate=!omitEnvironmentDropdown && std.objectHas(environmentStageSelectorHash, 'environment'),
      defaultDatasource=datasource.defaultDatasourceForService(metricsCatalogServiceInfo)
    )
    .addAnnotationIf(metricsCatalogServiceInfo.getProvisioning().runway, commonAnnotations.deploymentsForRunway(type))
    .addPanels(
      headlineMetricsRow(
        serviceType=type,
        startRow=0,
        rowTitle='🌡️ Aggregated Service Level Indicators (𝙎𝙇𝙄𝙨)',
        selectorHash=selectorHash,
        stableIdPrefix='',
        showApdex=metricsCatalogServiceInfo.hasApdex(),
        showErrorRatio=metricsCatalogServiceInfo.hasErrorRatio(),
        showOpsRate=metricsCatalogServiceInfo.hasRequestRate(),
        showSaturationCell=std.length(metricsCatalogServiceInfo.applicableSaturationTypes()) > 0,
        compact=false,
        rowHeight=10
      )
    );


  d {
    overviewTrailer()::
      self.trailer(),
  };

{
  overview:: overviewDashboard,
}
