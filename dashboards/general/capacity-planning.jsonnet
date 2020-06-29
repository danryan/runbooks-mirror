local capacityPlanning = import 'capacity_planning.libsonnet';
local commonAnnotations = import 'common_annotations.libsonnet';
local grafana = import 'grafonnet/grafana.libsonnet';
local platformLinks = import 'platform_links.libsonnet';
local templates = import 'templates.libsonnet';
local dashboard = grafana.dashboard;
local row = grafana.row;
local template = grafana.template;
local basic = import 'basic.libsonnet';

local rowHeight = 8;
local colWidth = 12;

basic.dashboard(
  'Capacity Planning',
  tags=['general'],
  includeStandardEnvironmentAnnotations=false,
)
.addPanels(capacityPlanning.environmentCapacityPlanningPanels(''))
.trailer()
