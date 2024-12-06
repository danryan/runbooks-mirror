local elasticsearchLinks = import 'elasticlinkbuilder/elasticsearch_links.libsonnet';
local matching = import 'elasticlinkbuilder/matching.libsonnet';
local basic = import 'grafana/basic.libsonnet';
local layout = import 'grafana/layout.libsonnet';

{
  railsPanels(serviceType, serviceStage, startRow)::
    local formatConfig = {
      serviceType: serviceType,
      serviceStage: serviceStage,
    };

    local elasticFilters = [
      matching.matchFilter('json.type.keyword', serviceType),
      matching.matchFilter('json.stage.keyword', serviceStage),
    ];

    local elasticRailsDataLink = {
      url: elasticsearchLinks.buildElasticDiscoverSearchQueryURL('rails', elasticFilters),
      title: 'ElasticSearch: rails logs',
      targetBlank: true,
    };

    local elasticRailsVisDataLink = {
      url: elasticsearchLinks.buildElasticLineCountVizURL('rails', elasticFilters),
      title: 'ElasticSearch: workhorse visualization',
      targetBlank: true,
    };

    layout.grid([
      basic.latencyTimeseries(
        title='p95 Latency Estimate',
        description='95th percentile Latency. Lower is better',
        query=|||
          histogram_quantile(0.95,
            sum(job_environment:gitlab_transaction_duration_seconds_bucket:rate5m{
              environment="$environment",
              type="%(serviceType)s",
              stage="%(serviceStage)s"
            }) by (le, job)
          )
        ||| % formatConfig,
        legendFormat='{{ job }}',
        format='s',
        min=0.05,
        yAxisLabel='Latency',
        interval='1m',
        intervalFactor=1,
        logBase=10
      )
      .addDataLink(elasticRailsDataLink)
      .addDataLink(elasticRailsVisDataLink),
      basic.timeseries(
        title='Rails Total Time',
        description='Seconds of Rails processing, per second',
        query=|||
          sum(
            job_environment:gitlab_transaction_duration_seconds_sum:rate1m{
              environment="$environment",
              type="%(serviceType)s",
              stage="%(serviceStage)s"}
          ) by (job)
        ||| % formatConfig,
        legendFormat='{{ job }}',
        interval='1m',
        intervalFactor=2,
        format='s',
        legend_show=true,
      )
      .addDataLink(elasticRailsDataLink)
      .addDataLink(elasticRailsVisDataLink),
      basic.timeseries(
        title='Rails Queue Time',
        description='Time spend waiting for a rails worker',
        query=|||
          sum(
            rate(
              gitlab_transaction_rails_queue_duration_total{
                environment="$environment",
                type="%(serviceType)s",
                stage="%(serviceStage)s"}
                [$__interval]
            )
          ) by (job)
        ||| % formatConfig,
        legendFormat='{{ job }}',
        interval='1m',
        intervalFactor=2,
        format='s',
        legend_show=true,
      )
      .addDataLink(elasticRailsDataLink)
      .addDataLink(elasticRailsVisDataLink),
      basic.timeseries(
        title='Cache Operations',
        description='Cache Operations per Second',
        query=|||
          sum(
            rate(
              gitlab_cache_operations_total{
                environment="$environment",
                type="%(serviceType)s",
                stage="%(serviceStage)s"}[$__interval]
            )
          ) by (job)
        ||| % formatConfig,
        legendFormat='{{ job }}',
        interval='1m',
        intervalFactor=10,  // High interval as we don't have a recording rule yet
        legend_show=true,
      )
      .addDataLink(elasticRailsDataLink)
      .addDataLink(elasticRailsVisDataLink),
      basic.timeseries(
        title='gitlab-rails Process restarts',
        description='The number of times this process restarted in a given period, including children workers. Restarts are associated with poor client experience, so lower is better.',
        yAxisLabel='Process restarts',
        query=|||
          sum(
            changes(
              ruby_process_start_time_seconds{
                environment="$environment",
                type="%(serviceType)s",
                stage="%(serviceStage)s",
                job="gitlab-rails"
              }[$__interval]
            )
          )
        ||| % formatConfig,
        legendFormat='process restarts',
        interval='1m',
        intervalFactor=2,
      )
      .addDataLink(elasticRailsDataLink)
      .addDataLink(elasticRailsVisDataLink),
      basic.queueLengthTimeseries(
        title='Database load balancer: average secondary connections per client',
        description='This graph shows the average number of secondary database connections\n        per process. A value of zero indicates that the secondary replicas are unreachable.',
        yAxisLabel='Average connections',
        query=|||
          avg(
            avg_over_time(
              db_load_balancing_hosts{
                environment="$environment",
                type="%(serviceType)s",
                stage="%(serviceStage)s"}[$__interval]
            )
          ) by (job)
        ||| % formatConfig,
        legendFormat='{{ job }}',
        interval='1m',
        intervalFactor=2,
      )
      .addDataLink(elasticRailsDataLink)
      .addDataLink(elasticRailsVisDataLink),
      basic.timeseries(
        title='Middleware check path traversal executions rate',
        description='Middleware check path traversal executions rate.',
        legendFormat='request rejected: {{request_rejected}}',
        query=|||
          sum by(request_rejected)(
            rate(
              gitlab_sli_path_traversal_check_request_apdex_total{
                environment="$environment",
                type="%(serviceType)s",
                stage="%(serviceStage)s",
                job="gitlab-rails"
              }[$__rate_interval]
            )
          )
        ||| % formatConfig,
        interval='1m',
        intervalFactor=2
      ),
      basic.percentageTimeseries(
        title='Middleware check path traversal execution time Apdex',
        description='Apdex of the middleware check path traversal executions with a threshold of 1ms.',
        yAxisLabel='Apdex %',
        legendFormat='request rejected: {{request_rejected}}',
        query=|||
          sum by(request_rejected)(
            rate(
              gitlab_sli_path_traversal_check_request_apdex_success_total{
                environment="$environment",
                type="%(serviceType)s",
                stage="%(serviceStage)s",
                job="gitlab-rails"
              }[$__rate_interval]
            )
          ) /
          sum by(request_rejected)(
            rate(
              gitlab_sli_path_traversal_check_request_apdex_total{
                environment="$environment",
                type="%(serviceType)s",
                stage="%(serviceStage)s",
                job="gitlab-rails"
              }[$__rate_interval]
            )
          )
        ||| % formatConfig,
        interval='1m',
        intervalFactor=2
      ),
    ], cols=2, rowHeight=10, startRow=startRow),

}
