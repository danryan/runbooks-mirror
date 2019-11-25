local grafana = import 'grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local seriesOverrides = import 'series_overrides.libsonnet';
local commonAnnotations = import 'common_annotations.libsonnet';
local promQuery = import 'prom_query.libsonnet';
local templates = import 'templates.libsonnet';
local colors = import 'colors.libsonnet';
local platformLinks = import 'platform_links.libsonnet';
local capacityPlanning = import 'capacity_planning.libsonnet';
local layout = import 'layout.libsonnet';
local basic = import 'basic.libsonnet';
local redisCommon = import 'redis_common_graphs.libsonnet';
local nodeMetrics = import 'node_metrics.libsonnet';
local keyMetrics = import 'key_metrics.libsonnet';
local serviceCatalogLinks = import 'service_catalog_links.libsonnet';
local row = grafana.row;
local template = grafana.template;
local graphPanel = grafana.graphPanel;
local annotation = grafana.annotation;
local text = grafana.text;

{
  rcaLayout(sections)::
    std.flattenArrays(
      std.mapWithIndex(
        function(index, section)
          local panel = if std.objectHas(section, 'panel') then
            section.panel
          else
            basic.timeseries(
              title='',
              query=section.query,
              legendFormat=if std.objectHas(section, 'legendFormat') then section.legendFormat else '',
              format='short',
              interval='1m',
              linewidth=1,
              intervalFactor=5,
            );
          [
            text.new(
              title='',
              mode='markdown',
              content=section.description
            ) + {
              gridPos: {
                x: 0,
                y: index * 12,
                w: 6,
                h: 12,
              },
            },
            panel {
              gridPos: {
                x: 6,
                y: index * 12,
                w: 18,
                h: 12,
              },
            },

          ],
        sections
      )
    ),

}
