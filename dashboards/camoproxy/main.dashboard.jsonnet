local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local basic = import 'grafana/basic.libsonnet';
local layout = import 'grafana/layout.libsonnet';
local promQuery = import 'grafana/prom_query.libsonnet';
local serviceDashboard = import 'service_dashboard.libsonnet';
local row = grafana.row;

local trafficPanel() =
  basic.timeseries(
    'Traffic',
    description='Traffic, in bytes per second',
    query='sum(rate(camo_response_size_bytes_sum{env="$environment"}[$__interval]))',
    format='B'
  );

local eventPanel() =
  basic.timeseries(
    'Request Failures',
    description='Failed requests',
    query='sum(rate(camo_proxy_reponses_failed_total{env="$environment"}[$__interval]))',
    legendFormat='Failed Requests',
  )
  .addTarget(
    promQuery.target(
      'sum(rate(camo_proxy_content_length_exceeded_total{env="$environment"}[$__interval]))',
      legendFormat='Content Length Exceeded - --max-size exceeded',
    )
  )
  .addTarget(
    promQuery.target(
      'sum(rate(camo_proxy_reponses_truncated_total{env="$environment"}[$__interval]))',
      legendFormat='Response Truncated - --max-size exceeded',
    )
  )
  .addTarget(
    promQuery.target(
      'sum(rate(camo_responses_total{env="$environment",code="504"}[$__interval]))',
      legendFormat='504 - Gateway Timeout - maybe --timeout exceeded',
    )
  );


serviceDashboard.overview('camoproxy', 'sv')
.addPanel(row.new(title='Proxy'), gridPos={ x: 0, y: 1000, w: 24, h: 1 })
.addPanels(layout.grid([
  trafficPanel(),
  eventPanel(),
], cols=2, rowHeight=10, startRow=1000))
.overviewTrailer()
