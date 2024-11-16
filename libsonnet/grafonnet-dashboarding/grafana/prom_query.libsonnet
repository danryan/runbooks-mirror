local g = import 'grafonnet-dashboarding/grafana/g.libsonnet';
local prometheus = g.query.prometheus;
local config = import 'gitlab-metrics-config.libsonnet';

{
  query(
    expr,
    format='time_series',
    intervalFactor=1,
    legendFormat='',
    datasource='$PROMETHEUS_DS',
    interval='1m',
    instant=null,
  )::
    prometheus.new(datasource, expr)
    + prometheus.withInterval(interval)
    + prometheus.withFormat(format)
    + prometheus.withInstant(instant == true)
    + prometheus.withLegendFormat(legendFormat),
}
