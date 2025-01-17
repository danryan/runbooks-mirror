local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local basic = import 'grafana/basic.libsonnet';
local layout = import 'grafana/layout.libsonnet';
local promQuery = import 'grafana/prom_query.libsonnet';
local graphPanel = grafana.graphPanel;
local row = grafana.row;
local dashboardHelpers = import 'stage-groups/verify-runner/dashboard_helpers.libsonnet';

// a-z ordered, without the p_ prefix
local partitionedTables = [
  'ci_build_names',
  'ci_builds',
  'ci_builds_execution_configs',
  'ci_builds_metadata',
  'ci_job_annotations',
  'ci_job_artifacts',
  'ci_pipeline_variables',
  'ci_pipelines',
  'ci_runner_machine_builds',
  'ci_stages',
];

local partitionedTablesFilter =
  std.join('|', std.flattenArrays(std.map((function(x) [x, x + '_\\\\d+']), partitionedTables)));

local formatConfig = {
  serviceType: 'patroni-ci',
  tableNames: partitionedTablesFilter,
};

dashboardHelpers.dashboard(
  'CI data partitions tracking',
  tags=[]
)
.addRowGrid(
  'Current partition',
  startRow=1000,
  collapse=false,
  panels=[
    basic.timeseries(
      title='Pipeline creation',
      description='Number of pipelines created per partition',
      query=|||
        sum(rate(pipelines_created_total{environment="$environment"}[$__interval])) by (partition_id) != 0
      ||| % formatConfig,
      legendFormat='{{ partition_id }}',
      format='ops',
      interval='1m',
      intervalFactor=2,
      yAxisLabel='',
      legend_show=true,
      linewidth=2
    ),
  ]
)
.addRowGrid(
  'Table size',
  startRow=2000,
  collapse=false,
  panels=[
    basic.timeseries(
      title='Table size for each partition',
      query=|||
        max(pg_total_relation_size_bytes{type="%(serviceType)s", environment="$environment", relname=~"%(tableNames)s"}) by (relname)
      ||| % formatConfig,
      legendFormat='{{ relname }}',
      format='bytes',
      interval='1m',
      intervalFactor=2,
      yAxisLabel='',
      legend_show=true,
      linewidth=2
    ),
    basic.timeseries(
      title='Partition growth rate',
      query=|||
        max(rate(pg_total_relation_size_bytes{type="%(serviceType)s", environment="$environment", relname=~"%(tableNames)s"}[$__interval])) by (relname)
      ||| % formatConfig,
      legendFormat='{{ relname }}',
      format='Bps',
      interval='1m',
      intervalFactor=2,
      yAxisLabel='',
      legend_show=true,
      linewidth=2
    ),
  ]
)
.addRowGrid(
  'Database nodes query stats',
  startRow=3000,
  collapse=false,
  panels=[
    basic.timeseries(
      title='Total Time in Queries per Node',
      description='Total number of seconds spent by pgbouncer when actively connected to PostgreSQL, executing queries - stats.total_query_time',
      query=|||
        sum(rate(pgbouncer_stats_queries_duration_seconds_total{type="%(serviceType)s", environment="$environment"}[$__interval])) by (fqdn)
      ||| % formatConfig,
      legendFormat='{{ fqdn }}',
      format='ops',
      interval='1m',
      intervalFactor=2,
      yAxisLabel='',
      legend_show=true,
      linewidth=2
    ),
    basic.timeseries(
      title='Time in Transaction per Server',
      description='Total number of seconds spent by pgbouncer when connected to PostgreSQL in a transaction, either idle in transaction or executing queries - stats.total_xact_time',
      query=|||
        sum(rate(pgbouncer_stats_server_in_transaction_seconds_total{type="%(serviceType)s", environment="$environment"}[$__interval])) by (fqdn)
      ||| % formatConfig,
      legendFormat='{{ fqdn }}',
      format='s',
      interval='1m',
      intervalFactor=2,
      yAxisLabel='',
      legend_show=true,
      linewidth=2
    ),
  ],
)
.addRowGrid(
  'Database nodes CPU stats',
  startRow=4000,
  collapse=false,
  panels=[
    graphPanel.new(
      'Node CPU',
      linewidth=1,
      fill=0,
      description='The amount of non-idle time consumed by nodes for this service',
      datasource='$PROMETHEUS_DS',
      decimals=2,
      sort='decreasing',
      legend_show=false,
      legend_values=false,
      legend_alignAsTable=false,
      legend_hideEmpty=true,
    )
    .addTarget(  // Primary metric
      promQuery.target(
        |||
          avg(instance:node_cpu_utilization:ratio{type="%(serviceType)s", environment="$environment"}) by (fqdn)
        ||| % formatConfig,
        legendFormat='{{ fqdn }}',
        intervalFactor=1,
      )
    )
    .resetYaxes()
    .addYaxis(
      format='percentunit',
      label='Average CPU Utilization',
    )
    .addYaxis(
      format='short',
      max=1,
      min=0,
      show=false,
    ),
    basic.saturationTimeseries(
      'Node Maximum Single Core Utilization',
      description='The maximum utilization of a single core on each node. Lower is better',
      query=
      |||
        max(1 - rate(node_cpu_seconds_total{type="%(serviceType)s", environment="$environment", mode="idle"}[$__interval])) by (fqdn)
      ||| % formatConfig,
      legendFormat='{{ fqdn }}',
      legend_show=false,
      linewidth=1
    ),
  ],
)
.addRowGrid(
  'Autovacuum stats',
  startRow=5000,
  collapse=false,
  panels=[
    basic.timeseries(
      title='Autovacuum age',
      description='Total number of seconds spent vacuuming the tables',
      query=|||
        sum(pg_stat_activity_autovacuum_age_in_seconds{type="%(serviceType)s", environment="$environment", relname!~".*\\(to prevent wraparound\\)"} / 3600) by(relname)
      ||| % formatConfig,
      legendFormat='{{ relname }}',
      format='h',
      interval='1m',
      intervalFactor=2,
      yAxisLabel='',
      legend_show=true,
      linewidth=2
    ),
    basic.timeseries(
      title='Wraparound autovacuum age',
      description='Total number of seconds spent vacuuming the tables in transaction wraparound prevention mode',
      query=|||
        sum(pg_stat_activity_autovacuum_age_in_seconds{type="%(serviceType)s", environment="$environment", relname=~".*\\(to prevent wraparound\\)"} / 3600) by(relname)
      ||| % formatConfig,
      legendFormat='{{ relname }}',
      format='h',
      interval='1m',
      intervalFactor=2,
      yAxisLabel='',
      legend_show=true,
      linewidth=2
    ),
  ],
)
.addRowGrid(
  'Tuple stats',
  startRow=6000,
  collapse=false,
  panels=[
    basic.timeseries(
      title='Dead tuples',
      description='Total number of dead tuples per table',
      query=|||
        sum(rate(pg_stat_user_tables_n_dead_tup{type="%(serviceType)s", environment="$environment", relname=~"%(tableNames)s"}[$__interval])) by(relname) != 0
      ||| % formatConfig,
      legendFormat='{{ relname }}',
      interval='1m',
      linewidth=2,
      decimals=0
    ),
    basic.timeseries(
      title='Live tuples',
      description='Total number of live tuples per table',
      query=|||
        sum(rate(pg_stat_user_tables_n_live_tup{type="%(serviceType)s", environment="$environment", relname=~"%(tableNames)s"}[$__interval])) by(relname) != 0
      ||| % formatConfig,
      legendFormat='{{ relname }}',
      interval='1m',
      linewidth=2,
      decimals=0
    ),
  ]
)
.addRowGrid(
  'Tuple ops rate',
  startRow=7000,
  collapse=false,
  panels=[
    basic.timeseries(
      title='Tuple inserts',
      description='Number of records inserted for each table',
      query=|||
        sum(rate(pg_stat_user_tables_n_tup_ins{type="%(serviceType)s", environment="$environment", relname=~"%(tableNames)s"}[$__interval])) by (relname) != 0
      ||| % formatConfig,
      legendFormat='{{ relname }}',
      format='ops',
      interval='1m',
      intervalFactor=2,
      yAxisLabel='',
      legend_show=true,
      linewidth=2
    ),
    basic.timeseries(
      title='Tuple updates',
      description='Number of records updated for each table',
      query=|||
        sum(rate(pg_stat_user_tables_n_tup_upd{type="%(serviceType)s", environment="$environment", relname=~"%(tableNames)s"}[$__interval])) by (relname) != 0
      ||| % formatConfig,
      legendFormat='{{ relname }}',
      format='ops',
      interval='1m',
      intervalFactor=2,
      yAxisLabel='',
      legend_show=true,
      linewidth=2
    ),
    basic.timeseries(
      title='Tuple deletes',
      description='Number of records deleted for each table',
      query=|||
        sum(rate(pg_stat_user_tables_n_tup_del{type="%(serviceType)s", environment="$environment", relname=~"%(tableNames)s"}[$__interval])) by (relname) != 0
      ||| % formatConfig,
      legendFormat='{{ relname }}',
      format='ops',
      interval='1m',
      intervalFactor=2,
      yAxisLabel='',
      legend_show=true,
      linewidth=2
    ),
  ]
)
