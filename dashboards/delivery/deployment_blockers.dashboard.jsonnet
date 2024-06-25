local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local basic = import 'grafana/basic.libsonnet';
local template = grafana.template;
local promQuery = import 'grafana/prom_query.libsonnet';
local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';
local row = grafana.row;
local layout = import 'grafana/layout.libsonnet';
local mimirHelper = import 'services/lib/mimir-helpers.libsonnet';

local totalBlockersCount = 'sum by (root_cause) (last_over_time(delivery_deployment_blocker_count{root_cause=~".+", root_cause!="RootCause::FlakyTest"}[1d]))';
local totalGprdHoursBlocked = 'sum by (root_cause) (last_over_time(delivery_deployment_hours_blocked{target_env="gprd", root_cause=~".+", root_cause!="RootCause::FlakyTest"}[1d]))';
local totalGstgHoursBlocked = 'sum by (root_cause) (last_over_time(delivery_deployment_hours_blocked{target_env="gstg", root_cause=~".+", root_cause!="RootCause::FlakyTest"}[1d]))';
local blockersCount = 'max by (week) (last_over_time(delivery_deployment_blocker_count{root_cause="$root_cause"}[1d]))';
local gprdHoursBlocked = 'max by (week) (last_over_time(delivery_deployment_hours_blocked{root_cause="$root_cause", target_env="gprd"}[1d]))';
local gstgHoursBlocked = 'max by (week) (last_over_time(delivery_deployment_hours_blocked{root_cause="$root_cause", target_env="gstg"}[1d]))';

local textPanel =
  g.panel.text.new('')
  + g.panel.text.options.withMode("markdown")
  + g.panel.text.options.withContent(|||
      # Deployment Blockers

      Deployment failures are currently automatically captured under [release/tasks issues](https://gitlab.com/gitlab-org/release/tasks/-/issues).
      Release managers are responsible for labeling these failures with appropriate `RootCause::*` labels. By the start of the following week (Monday), the `deployments:blockers_report` scheduled pipeline in the [release/tools](https://ops.gitlab.net/gitlab-org/release/tools/-/pipeline_schedules) repo reviews the labeled issues and generates a weekly deployment blockers issue, like this [one](https://gitlab.com/gitlab-org/release/tasks/-/issues/11125).

      This dashboard tracks the trend of recurring root causes for deployment blockers. Each root cause is displayed in separate rows with three panels: one for the count of blockers, one for `gprd` hours blocked, and one for `gstg` hours blocked. At the top, there is an overview of the failure types, including the total calculations for the entire specified time window.

      Links:
      - [List of root causes](https://gitlab.com/gitlab-org/release/tasks/-/labels?subscribed=&sort=relevance&search=RootCause)
      - [Deployments metrics review](https://gitlab.com/groups/gitlab-com/gl-infra/-/epics/1192)
    |||);

local barChartPanel(name, query) =
  g.panel.barChart.new('')
  + g.panel.barChart.queryOptions.withInterval('2d')
  + g.panel.barChart.options.withOrientation("horizontal")
  + g.panel.barChart.options.legend.withDisplayMode("table")
  + g.panel.barChart.options.legend.withShowLegend(true)
  + g.panel.barChart.options.legend.withPlacement("bottom")
  + g.panel.barChart.options.legend.withCalcs(["sum"])
  + g.panel.barChart.standardOptions.withDisplayName(name)
  + g.panel.barChart.standardOptions.color.withMode("thresholds")
  + g.panel.barChart.queryOptions.withTargetsMixin([
    g.query.prometheus.new(
      '$PROMETHEUS_DS',
      query,
    )
    + g.query.prometheus.withFormat("time_series")
    + g.query.prometheus.withLegendFormat('{{root_cause}}'),
  ])
  + g.panel.barChart.queryOptions.withTransformations([
    g.panel.barChart.queryOptions.transformation.withId("reduce")
    + g.panel.barChart.queryOptions.transformation.withOptions({ reducers: ['sum'] })
  ]);

local trendPanel(title, query, name) =
  g.panel.trend.new(title)
  + g.panel.trend.queryOptions.withInterval('2d')
  + g.panel.trend.options.withXField("week_index")
  + g.panel.trend.options.legend.withDisplayMode('list')
  + g.panel.trend.options.legend.withPlacement("bottom")
  + g.panel.trend.fieldConfig.defaults.custom.withDrawStyle("line")
  + g.panel.trend.fieldConfig.defaults.custom.withLineInterpolation("linear")
  + g.panel.trend.fieldConfig.defaults.custom.withLineWidth(1)
  + g.panel.trend.fieldConfig.defaults.custom.withShowPoints("always")
  + g.panel.trend.fieldConfig.defaults.custom.withSpanNulls(true)
  + g.panel.trend.fieldConfig.defaults.custom.withAxisBorderShow(true)
  + g.panel.trend.fieldConfig.defaults.custom.withAxisSoftMin(1)
  + g.panel.trend.standardOptions.withDisplayName(name)
  + g.panel.trend.standardOptions.withDecimals(0)
  + g.panel.trend.standardOptions.withUnit("short")
  + g.panel.trend.standardOptions.withMin(1)
  + g.panel.trend.standardOptions.color.withMode("palette-classic")
  + g.panel.trend.standardOptions.withOverrides([
    g.panel.trend.standardOptions.override.byName.new('week_index')
    + g.panel.trend.standardOptions.override.byName.withPropertiesFromOptions(
      g.panel.trend.fieldConfig.defaults.custom.withAxisLabel("week_index")
      + g.panel.trend.fieldConfig.defaults.custom.withAxisPlacement("hidden")
    )
  ])
  + g.panel.trend.queryOptions.withTargetsMixin([
    g.query.prometheus.new(
      '$PROMETHEUS_DS',
      query,
    )
    + g.query.prometheus.withFormat("table"),
  ])
  + g.panel.trend.queryOptions.withTransformations([
    g.panel.trend.queryOptions.transformation.withId("calculateField")
    + g.panel.trend.queryOptions.transformation.withOptions({
      alias: "count",
      binary: {
        left: "week"
      },
      mode: "index",
      reduce: {
        reducer: "sum"
      }
    }),
    g.panel.trend.queryOptions.transformation.withId("calculateField")
    + g.panel.trend.queryOptions.transformation.withOptions({
      alias: "week_index",
      binary: {
        left: "count",
        right: "1"
      },
      mode: "binary",
      reduce: {
        reducer: "sum"
      }
    }),
    g.panel.trend.queryOptions.transformation.withId("organize")
    + g.panel.trend.queryOptions.transformation.withOptions({
      excludeByName: {
        Time: false,
        count: true
      },
      includeByName: {},
      indexByName: {},
      renameByName: {},
    })
  ]);

local tablePanel =
  g.panel.table.new('')
  + g.panel.table.queryOptions.withInterval('2d')
  + g.panel.table.fieldConfig.defaults.custom.withFilterable(true)
  + g.panel.table.options.withShowHeader(true)
  + g.panel.table.standardOptions.color.withMode("thresholds")
  + g.panel.table.queryOptions.withTargetsMixin([
    g.query.prometheus.new(
      '$PROMETHEUS_DS',
      blockersCount,
    )
    + g.query.prometheus.withFormat("time_series")
    + g.query.prometheus.withRefId("blockers_count"),

    g.query.prometheus.new(
      '$PROMETHEUS_DS',
      gprdHoursBlocked,
    )
    + g.query.prometheus.withFormat("time_series")
    + g.query.prometheus.withRefId("gprd_hours_blocked"),

    g.query.prometheus.new(
      '$PROMETHEUS_DS',
      gstgHoursBlocked,
    )
    + g.query.prometheus.withFormat("time_series")
    + g.query.prometheus.withRefId("gstg_hours_blocked"),

  ])
  + g.panel.table.queryOptions.withTransformations([
    g.panel.table.queryOptions.transformation.withId("timeSeriesTable")
    + g.panel.table.queryOptions.transformation.withOptions({}),
    g.panel.table.queryOptions.transformation.withId("merge")
    + g.panel.table.queryOptions.transformation.withOptions({}),
    g.panel.table.queryOptions.transformation.withId("calculateField")
    + g.panel.table.queryOptions.transformation.withOptions({
      alias: "count",
      mode: "index",
      reduce: {
        reducer: "sum"
      }
    }),
    g.panel.table.queryOptions.transformation.withId("calculateField")
    + g.panel.table.queryOptions.transformation.withOptions({
      alias: "week_index",
      binary: {
        left: "count",
        right: "1"
      },
      mode: "binary",
      reduce: {
        reducer: "sum"
      }
    }),
    g.panel.table.queryOptions.transformation.withId("organize")
    + g.panel.table.queryOptions.transformation.withOptions({
      excludeByName: {
        count: true
      },
      includeByName: {},
      indexByName: {},
      renameByName: {
        "Trend #blockers_count": "blockers_count",
        "Trend #gprd_hours_blocked": "gprd_hours_blocked",
        "Trend #gstg_hours_blocked": "gstg_hours_blocked"
      }
    })
  ]);

basic.dashboard(
  'Deployment Blockers',
  tags=['release'],
  editable=true,
  time_from='now-90d',
  time_to='now',
  includeStandardEnvironmentAnnotations=false,
  includeEnvironmentTemplate=false,
  defaultDatasource=mimirHelper.mimirDatasource('gitlab-ops'),
)
.addTemplate(
  template.new(
    'root_cause',
    '$PROMETHEUS_DS',
    'label_values(delivery_deployment_blocker_count{root_cause!="RootCause::FlakyTest"},root_cause)',
    includeAll=true,
    multi=true,
  )
)
.addPanel(textPanel, gridPos={ x: 0, y: 0, w: 24, h: 7 })
.addPanel(
  row.new(title='Overview'),
  gridPos={ x: 0, y: 7, w: 24, h: 1 },
)
.addPanel(barChartPanel('blockers_count', totalBlockersCount), gridPos={ x: 0, y: 8, w: 8, h: 10 })
.addPanel(barChartPanel('gprd_hours_blocked', totalGprdHoursBlocked), gridPos={ x: 8, y: 8, w: 8, h: 10 })
.addPanel(barChartPanel('gstg_hours_blocked', totalGstgHoursBlocked), gridPos={ x: 16, y: 8, w: 8, h: 10 })
.addPanel(
  row.new(title='$root_cause', repeat='root_cause'),
  gridPos={ x: 0, y: 18, w: 24, h: 1 },
)
.addPanel(trendPanel('Blockers Count for $root_cause', blockersCount, 'blockers_count'), gridPos={ x: 0, y: 19, w: 8, h: 8 })
.addPanel(trendPanel('gprd Hours Blocked for $root_cause', gprdHoursBlocked, 'gprd_hours_blocked'), gridPos={ x: 8, y: 19, w: 8, h: 8 })
.addPanel(trendPanel('gstg Hours Blocked for $root_cause', gstgHoursBlocked, 'gstg_hours_blocked'), gridPos={ x: 16, y: 19, w: 8, h: 8 })
.addPanel(tablePanel, gridPos={ x: 0, y: 27, w: 24, h: 8 })
.addPanel(row.new(''), gridPos={ x: 0, y: 100000, w: 24, h: 1 })
.trailer()
