local capacityPlanning = import 'capacity_planning.libsonnet';
local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local basic = import 'grafana/basic.libsonnet';
local layout = import 'grafana/layout.libsonnet';
local promQuery = import 'grafana/prom_query.libsonnet';
local seriesOverrides = import 'grafana/series_overrides.libsonnet';
local templates = import 'grafana/templates.libsonnet';
local keyMetrics = import 'key_metrics.libsonnet';
local nodeMetrics = import 'node_metrics.libsonnet';
local pgbouncerCommonGraphs = import 'pgbouncer_common_graphs.libsonnet';
local platformLinks = import 'platform_links.libsonnet';
local serviceCatalog = import 'service_catalog.libsonnet';
local dashboard = grafana.dashboard;
local row = grafana.row;
local template = grafana.template;
local graphPanel = grafana.graphPanel;
local annotation = grafana.annotation;
local serviceDashboard = import 'service_dashboard.libsonnet';

serviceDashboard.overview('pgbouncer', 'main')
.addPanel(
  row.new(title='pgbouncer Workload'),
  gridPos={
    x: 0,
    y: 1000,
    w: 24,
    h: 1,
  }
)
.addPanels(pgbouncerCommonGraphs.workloadStats('pgbouncer', startRow=2000))
.addPanel(
  row.new(title='pgbouncer Connection Pooling'),
  gridPos={
    x: 0,
    y: 3000,
    w: 24,
    h: 1,
  }
)
.addPanels(pgbouncerCommonGraphs.connectionPoolingPanels('pgbouncer', 3001))
.addPanel(
  row.new(title='pgbouncer Network'),
  gridPos={
    x: 0,
    y: 4000,
    w: 24,
    h: 1,
  }
)
.addPanels(pgbouncerCommonGraphs.networkStats('pgbouncer', 4001))
.addPanel(
  row.new(title='pgbouncer Client Transaction Utilisation'),
  gridPos={
    x: 0,
    y: 5000,
    w: 24,
    h: 1,
  }
)
.addPanels(
  layout.grid([
    basic.timeseries(
      title='Async Pool',
      description='Total async pool utilisation by job.',
      query=
      |||
        sum by (worker, stage) (rate(sidekiq_jobs_completion_seconds_sum{environment="$environment", env="$environment", monitor="app"}[$__interval]))
      |||,
      legendFormat='{{ worker }} - {{ stage }} stage',
      format='s',
      yAxisLabel='"Usage client transaction time/sec',
      interval='1m',
      intervalFactor=1,
      legend_show=false,
      linewidth=1
    ),
    basic.timeseries(
      title='Sync Pool',
      description='Total sync (web/api/git) pool utilisation by job.',
      query=
      |||
        sum by (controller, stage) (
          rate(gitlab_transaction_duration_seconds_sum{environment="$environment", env="$environment", monitor="app", type!="sidekiq", controller!="Grape"}[$__interval])
        )
        or
        label_replace(
          sum by (action, stage) (
            rate(gitlab_transaction_duration_seconds_sum{environment="$environment", env="$environment", monitor="app", type!="sidekiq", controller="Grape"}[$__interval])
          ),
          "controller", "$1", "action", "(.*)"
        )
      |||,
      legendFormat='{{ controller }} - {{ stage }} stage',
      format='s',
      yAxisLabel='"Usage client transaction time/sec',
      interval='1m',
      intervalFactor=1,
      legend_show=false,
      linewidth=1
    ),
  ], cols=2, startRow=5001)
)
.overviewTrailer()
