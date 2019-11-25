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
local railsCommon = import 'rails_common_graphs.libsonnet';
local seriesOverrides = import 'series_overrides.libsonnet';
local serviceCatalogLinks = import 'service_catalog_links.libsonnet';
local templates = import 'templates.libsonnet';
local unicornCommon = import 'unicorn_common_graphs.libsonnet';
local workhorseCommon = import 'workhorse_common_graphs.libsonnet';
local dashboard = grafana.dashboard;
local row = grafana.row;
local template = grafana.template;
local graphPanel = grafana.graphPanel;
local annotation = grafana.annotation;
local serviceHealth = import 'service_health.libsonnet';
local saturationDetail = import 'saturation_detail.libsonnet';

local selector = 'environment="$environment", type="git", stage="$stage"';

dashboard.new(
  'Overview',
  schemaVersion=16,
  tags=['overview'],
  timezone='utc',
  graphTooltip='shared_crosshair',
)
.addAnnotation(commonAnnotations.deploymentsForEnvironment)
.addAnnotation(commonAnnotations.deploymentsForEnvironmentCanary)
.addTemplate(templates.ds)
.addTemplate(templates.environment)
.addTemplate(templates.stage)
.addPanels(keyMetrics.headlineMetricsRow('git', '$stage', startRow=0))
.addPanel(serviceHealth.row('git', '$stage'), gridPos={ x: 0, y: 500 })
.addPanel(
  row.new(title='Workhorse'),
  gridPos={
    x: 0,
    y: 1000,
    w: 24,
    h: 1,
  }
)
.addPanels(workhorseCommon.workhorsePanels(serviceType='git', serviceStage='$stage', startRow=1001))
.addPanel(
  row.new(title='Unicorn'),
  gridPos={
    x: 0,
    y: 2000,
    w: 24,
    h: 1,
  }
)
.addPanels(unicornCommon.unicornPanels(serviceType='git', serviceStage='$stage', startRow=1001))

.addPanel(
  row.new(title='Rails'),
  gridPos={
    x: 0,
    y: 3000,
    w: 24,
    h: 1,
  }
)
.addPanels(railsCommon.railsPanels(serviceType='git', serviceStage='$stage', startRow=3001))
.addPanel(keyMetrics.keyServiceMetricsRow('git', '$stage'), gridPos={ x: 0, y: 4000 })
.addPanel(workhorseCommon.componentDetailsRow('git', selector), gridPos={ x: 0, y: 5000 })
.addPanel(unicornCommon.componentDetailsRow('git', selector), gridPos={ x: 0, y: 5100 })
.addPanel(nodeMetrics.nodeMetricsDetailRow(selector), gridPos={ x: 0, y: 6000 })
.addPanel(saturationDetail.saturationDetailPanels('git', '$stage', components=[
            'cpu',
            'disk_space',
            'memory',
            'open_fds',
            'single_node_cpu',
            'single_node_unicorn_workers',
            'workers',
          ]),
          gridPos={ x: 0, y: 7000, w: 24, h: 1 })
.addPanel(capacityPlanning.capacityPlanningRow('git', '$stage'), gridPos={ x: 0, y: 8000 })
+ {
  links+: platformLinks.triage + serviceCatalogLinks.getServiceLinks('git') + platformLinks.services,
}
