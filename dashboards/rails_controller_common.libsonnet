local elasticsearchLinks = import 'elasticlinkbuilder/elasticsearch_links.libsonnet';
local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local basic = import 'grafana/basic.libsonnet';
local layout = import 'grafana/layout.libsonnet';
local templates = import 'grafana/templates.libsonnet';
local selectors = import 'promql/selectors.libsonnet';

local row = grafana.row;

local elasticsearchLogSearchDataLink(type) = {
  url: elasticsearchLinks.buildElasticDiscoverSearchQueryURL(
    'rails',
    [
      elasticsearchLinks.matchFilter('json.type.keyword', type),
      elasticsearchLinks.matchFilter('json.controller.keyword', '$controller'),
    ],
    ['json.action.keyword:${action:lucene}']
  ),
  title: 'ElasticSearch: Rails logs',
  targetBlank: true,
};

{
  dashboard(type, defaultController, defaultAction)::
    local selector = {
      environment: '$environment',
      type: type,
      stage: '$stage',
      controller: '$controller',
      action: { re: '$action' },
    };

    local selectorString = selectors.serializeHash(selector);

    basic.dashboard(
      'Rails Controller',
      tags=['type:%s' % type, 'detail'],
      includeEnvironmentTemplate=true,
    )
    .addTemplate(templates.constant('type', type))
    .addTemplate(templates.stage)
    .addTemplate(templates.railsController(defaultController))
    .addTemplate(templates.railsControllerAction(defaultAction))
    .addPanels(
      layout.grid([
        basic.timeseries(
          stableId='request-rate',
          title='Request Rate',
          query='avg_over_time(controller_action:gitlab_transaction_duration_seconds_count:rate1m{%s}[$__interval])' % selectorString,
          legendFormat='{{ action }}',
          format='ops',
          yAxisLabel='Requests per Second',
        ).addDataLink(elasticsearchLogSearchDataLink(type)),
        basic.multiTimeseries(
          stableId='latency',
          title='Latency',
          queries=[{
            query: 'avg_over_time(controller_action:gitlab_transaction_duration_seconds:p99{%s}[$__interval])' % selectorString,
            legendFormat: '{{ action }} - p99',
          }, {
            query: 'avg_over_time(controller_action:gitlab_transaction_duration_seconds:p95{%s}[$__interval])' % selectorString,
            legendFormat: '{{ action }} - p95',
          }, {
            query: |||
              avg_over_time(controller_action:gitlab_transaction_duration_seconds_sum:rate1m{%(selector)s}[$__interval])
              /
              avg_over_time(controller_action:gitlab_transaction_duration_seconds_count:rate1m{%(selector)s}[$__interval])
            ||| % { selector: selectorString },
            legendFormat: '{{ action }} - mean',
          }],
          format='s',
        ).addDataLink(elasticsearchLogSearchDataLink(type)),
      ])
      +
      layout.rowGrid('SQL', [
        basic.timeseries(
          stableId='sql-requests-per-controller-request',
          title='SQL Requests per Controller Request',
          query=|||
            sum without (fqdn,instance) (
            rate(gitlab_sql_duration_seconds_count{%(selector)s}[$__interval])
            )
            /
            avg_over_time(controller_action:gitlab_transaction_duration_seconds_count:rate1m{%(selector)s}[$__interval])
          ||| % { selector: selectorString },
          legendFormat='{{ action }}',
        ),
        basic.timeseries(
          stableId='sql-latency-per-controller-request',
          title='SQL Latency per Controller Request',
          query=|||
            avg_over_time(controller_action:gitlab_sql_duration_seconds_sum:rate1m{%(selector)s}[$__interval])
            /
            avg_over_time(controller_action:gitlab_transaction_duration_seconds_count:rate1m{%(selector)s}[$__interval])
          ||| % { selector: selectorString },
          legendFormat='{{ action }}',
          format='s'
        ),
        basic.timeseries(
          stableId='sql-latency-per-sql-request',
          title='SQL Latency per SQL Request',
          query=|||
            sum without (fqdn,instance) (
            rate(gitlab_sql_duration_seconds_sum{%(selector)s}[$__interval])
            )
            /
            sum without (fqdn,instance) (
            rate(gitlab_sql_duration_seconds_count{%(selector)s}[$__interval])
            )
          ||| % { selector: selectorString },
          legendFormat='{{ action }}',
          format='s'
        ),
      ], startRow=201)
      +
      layout.rowGrid('Cache', [
        basic.timeseries(
          stableId='cache-operations',
          title='Cache Operations',
          query=|||
            sum without (fqdn, instance) (
            rate(gitlab_cache_operations_total{%(selector)s}[$__interval])
            )
          ||| % { selector: selectorString },
          legendFormat='{{ operation }}',
        ),
      ], startRow=301)
      +
      layout.rowGrid('Elasticsearch', [
        basic.multiQuantileTimeseries('Elasticsearch Time', selector, '{{ action }}', bucketMetric='http_elasticsearch_requests_duration_seconds_bucket', aggregators='controller, action'),
      ], startRow=401)
      +
      layout.rowGrid('External HTTP', [
        basic.timeseries(
          stableId='external-http',
          title='External HTTP calls',
          query=|||
            sum by (controller, action, code) (
            rate(gitlab_external_http_total{%(selector)s}[$__interval])
            )
          ||| % { selector: selectorString },
          legendFormat='{{ action }} - {{ code }}',
          format='ops',
        ),
        basic.multiTimeseries(
          stableId='external-http-latency',
          title='External HTTP Latency per call',
          queries=[{
            query: |||
              histogram_quantile(
                0.5,
                sum(
                  rate(
                    gitlab_external_http_duration_seconds_bucket{%s}[5m]
                  )
                ) by (action, le)
              )
            ||| % selectorString,
            legendFormat: '{{ action }} - p50',
          }, {
            query: |||
              histogram_quantile(
                0.9,
                sum(
                  rate(
                    gitlab_external_http_duration_seconds_bucket{%s}[5m]
                  )
                ) by (action, le)
              )
            ||| % selectorString,
            legendFormat: '{{ action }} - p90',
          }, {
            query: |||
              histogram_quantile(
                0.99,
                sum(
                  rate(
                    gitlab_external_http_duration_seconds_bucket{%s}[5m]
                  )
                ) by (action, le)
              )
            ||| % selectorString,
            legendFormat: '{{ action }} - p99',
          }],
          format='s',
        ),
      ], startRow=501)
      +
      layout.grid([])
    )
    .trailer(),
}
