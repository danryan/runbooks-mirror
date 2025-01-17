local datasource = import './datasource.libsonnet';
local metricsCatalogDashboards = import './metrics_catalog_dashboards.libsonnet';
local basic = import 'grafana/basic.libsonnet';
local layout = import 'grafana/layout.libsonnet';
local templates = import 'grafana/templates.libsonnet';
local singleMetricRow = import 'key-metric-panels/single-metric-row.libsonnet';
local metricsCatalog = import 'servicemetrics/metrics-catalog.libsonnet';

// TODO: remove the `location` label from the legends when we don't need it
// anymore after migrating to mimir.
// https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/3398
local dashboardForService(serviceType, serviceSLIsAggregationSet, componentSLIsAggregationSet) =
  local metricsCatalogServiceInfo = metricsCatalog.getService(serviceType);
  local formatConfig = { serviceType: serviceType };
  local selectorHash = { env: '$environment', environment: '$environment', type: serviceType, stage: '$stage' };

  local headlineRow =
    singleMetricRow.row(
      serviceType=serviceType,
      sli=null,
      aggregationSet=serviceSLIsAggregationSet,
      selectorHash=selectorHash,
      titlePrefix='Regional Service Aggregated ',
      stableIdPrefix='service-regional-%(serviceType)s' % formatConfig,
      legendFormatPrefix='{{ region }} {{ location }}',
      showApdex=metricsCatalogServiceInfo.hasApdex(),
      showErrorRatio=metricsCatalogServiceInfo.hasErrorRate(),
      showOpsRate=true,
      expectMultipleSeries=true
    );

  basic.dashboard(
    'Regional Detail',
    tags=['type:%(serviceType)s' % formatConfig, 'regional'],
    defaultDatasource=datasource.defaultDatasourceForService(metricsCatalogServiceInfo)
  )
  .addTemplate(templates.stage)
  .addPanels(
    layout.splitColumnGrid(headlineRow, [7, 1], startRow=10),
  )
  .addPanels(
    metricsCatalogDashboards.sliMatrixForService(
      title='🔬 Regional SLIs',
      aggregationSet=componentSLIsAggregationSet,
      serviceType=serviceType,
      selectorHash=selectorHash,
      startRow=1000,
      legendFormatPrefix='{{ region }} {{ location }}',
      expectMultipleSeries=true
    )
  )
  .trailer();

{
  dashboardForService:: dashboardForService,
}
