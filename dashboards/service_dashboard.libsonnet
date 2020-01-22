local basic = import 'basic.libsonnet';
local capacityPlanning = import 'capacity_planning.libsonnet';
local colors = import 'colors.libsonnet';
local commonAnnotations = import 'common_annotations.libsonnet';
local grafana = import 'grafonnet/grafana.libsonnet';
local keyMetrics = import 'key_metrics.libsonnet';
local layout = import 'layout.libsonnet';
local nodeMetrics = import 'node_metrics.libsonnet';
local platformLinks = import 'platform_links.libsonnet';
local promQuery = import 'prom_query.libsonnet';
local seriesOverrides = import 'series_overrides.libsonnet';
local serviceCatalog = import 'service_catalog.libsonnet';
local templates = import 'templates.libsonnet';
local dashboard = grafana.dashboard;
local row = grafana.row;
local template = grafana.template;
local graphPanel = grafana.graphPanel;
local annotation = grafana.annotation;
local serviceHealth = import 'service_health.libsonnet';
local saturationDetail = import 'saturation_detail.libsonnet';
local metricsCatalog = import 'metrics-catalog.libsonnet';
local metricsCatalogDashboards = import 'metrics_catalog_dashboards.libsonnet';

local overviewDashboard(type, tier) =
  local selector = 'environment="$environment", type="%s", stage="$stage"' % [type];
  local catalogServiceInfo = serviceCatalog.lookupService(type);
  local metricsCatalogServiceInfo = metricsCatalog.getService(type);

  basic.dashboard(
    'Overview',
    tags=['type:' + type, 'tier:' + tier, type],
  )
  .addTemplate(templates.stage)
  .addTemplate(templates.sigma)
  .addPanels(keyMetrics.headlineMetricsRow(type, '$stage', startRow=0))
  .addPanel(serviceHealth.row(type, '$stage'), gridPos={ x: 0, y: 10 })
  .addPanels(
    metricsCatalogDashboards.componentOverviewMatrix(
      type,
      startRow=20
    )
  )
  .addPanels(
    metricsCatalogDashboards.autoDetailRows(type, selector, startRow=100)
  )
  .addPanel(
    nodeMetrics.nodeMetricsDetailRow(selector),
    gridPos={
      x: 0,
      y: 300,
      w: 24,
      h: 1,
    }
  )
  .addPanel(
    saturationDetail.saturationDetailPanels(selector, components=metricsCatalogServiceInfo.saturationTypes),
    gridPos={ x: 0, y: 400, w: 24, h: 1 }
  );

{
  overview(type, tier):: overviewDashboard(type, tier) {
    _serviceType: type,
    _serviceTier: tier,
    overviewTrailer()::
      local s = self;
      s.addPanel(capacityPlanning.capacityPlanningRow(s._serviceType, '$stage'), gridPos={ x: 0, y: 100000 })
      + {
        links+: platformLinks.triage + serviceCatalog.getServiceLinks(s._serviceType) + platformLinks.services,
      },
  },

}
