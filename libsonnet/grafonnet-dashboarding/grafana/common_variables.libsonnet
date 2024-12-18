local g = import 'grafonnet-dashboarding/grafana/g.libsonnet';
local variable = g.dashboard.variable;
local query = variable.query;
local datasource = variable.datasource;

local defaultPrometheusDatasource = (import 'gitlab-metrics-config.libsonnet').defaultPrometheusDatasource;

// Variables are the new version of templates, arguably, it's a better name.
// Default constructor from grafonnet lib:
// new(
//   name,
//   datasource,
//   query,
//   label=null,
//   allValues=null,
//   tagValuesQuery='',
//   current=null,
//   hide='',
//   regex='',
//   refresh='never',
//   includeAll=false,
//   multi=false,
//   sort=0,
// )::

{
  ds(current=defaultPrometheusDatasource)::
    datasource.new('PROMETHEUS_DS', 'prometheus')
    + datasource.generalOptions.withCurrent(if current != null then current else defaultPrometheusDatasource),

  environment::
    query.new('environment')
    + query.queryTypes.withLabelValues('env', metric='gitlab_service_ops:rate_1h')
    + query.refresh.onLoad()
    + query.withSort()
    + query.generalOptions.withCurrent('gprd')
    + query.withDatasourceFromVariable($.ds()),

}
