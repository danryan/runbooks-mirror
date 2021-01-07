local rison = import 'rison.libsonnet';

local grafanaTimeFrom = '${__from:date:iso}';
local grafanaTimeTo = '${__to:date:iso}';
local grafanaTimeRange = "&_g=(time:(from:'" + grafanaTimeFrom + "',to:'" + grafanaTimeTo + "'))";

// Builds an ElasticSearch match filter clause
local matchFilter(field, value) =
  {
    query: {
      match: {
        [field]: {
          query: value,
          type: 'phrase',
        },
      },

    },
  };

local matchInFilter(field, possibleValues) =
  {
    query: {
      bool: {
        should: [{ match_phrase: { [field]: possibleValue } } for possibleValue in possibleValues],
        minimum_should_match: 1,
      },
    },
  };

// Builds an ElasticSearch range filter clause
local rangeFilter(field, gteValue, lteValue) =
  {
    query: {
      range: {
        [field]: {
          [if gteValue != null then 'gte']: gteValue,
          [if lteValue != null then 'lte']: lteValue,
        },
      },
    },
  };

local existsFilter(field) =
  {
    exists: {
      field: field,
    },
  };

local mustNot(filter) =
  filter {
    meta+: {
      negate: true,
    },
  };

local matcher(fieldName, matchInfo) =
  if std.isString(matchInfo) then
    matchFilter(fieldName, matchInfo)
  else if std.isArray(matchInfo) then
    matchInFilter(fieldName, matchInfo);

local statusCode(field) =
  [rangeFilter(field, gteValue=500, lteValue=null)];

local indexDefaults = {
  kibanaEndpoint: 'https://log.gprd.gitlab.net/app/kibana',
  prometheusLabelMappings: {},
};

// These are default prometheus label mappings, for mapping
// between prometheus labels and their equivalent ELK fields
// We know that these fields exist on most of our structured logs
// so we can safely map from the given labels to the fields in all cases
local defaultPrometheusLabelMappings = {
  type: 'json.type',
  stage: 'json.stage',
};

local indexCatalog = {
  // Improve these logs when https://gitlab.com/gitlab-com/gl-infra/infrastructure/-/issues/11221 is addressed
  camoproxy: indexDefaults {
    timestamp: '@timestamp',
    indexPattern: 'AWz5hIoSGphUgZwzAG7q',
    defaultColumns: ['json.hostname', 'json.camoproxy_message', 'json.camoproxy_err'],
    defaultSeriesSplitField: 'json.hostname.keyword',
    failureFilter: [existsFilter('json.camoproxy_err')],
    //defaultLatencyField: 'json.grpc.time_ms',
    //latencyFieldUnitMultiplier: 1000,
  },

  gitaly: indexDefaults {
    timestamp: 'json.time',
    indexPattern: 'AW5F1OHTiGcMMNRn84Di',
    defaultColumns: ['json.hostname', 'json.grpc.method', 'json.grpc.request.glProjectPath', 'json.grpc.code', 'json.grpc.time_ms'],
    defaultSeriesSplitField: 'json.grpc.method.keyword',
    failureFilter: [mustNot(matchFilter('json.grpc.code', 'OK')), existsFilter('json.grpc.code')],
    defaultLatencyField: 'json.grpc.time_ms',
    prometheusLabelMappings: {
      fqdn: 'json.fqdn',
    },
    latencyFieldUnitMultiplier: 1000,
  },

  monitoring_ops: indexDefaults {
    timestamp: '@timestamp',
    indexPattern: 'pubsub-monitoring-inf-ops',
    defaultColumns: ['json.hostname', 'json.msg', 'json.level'],
    defaultSeriesSplitField: 'json.hostname.keyword',
    failureFilter: [matchFilter('json.level', 'error')],
    kibanaEndpoint: 'https://nonprod-log.gitlab.net/app/kibana',
  },

  monitoring_gprd: indexDefaults {
    timestamp: '@timestamp',
    indexPattern: 'AW5ZoH2ddtvLTaJbch2P',
    defaultColumns: ['json.hostname', 'json.msg', 'json.level'],
    defaultSeriesSplitField: 'json.hostname.keyword',
    failureFilter: [matchFilter('json.level', 'error')],
  },

  pages: indexDefaults {
    timestamp: 'json.time',
    indexPattern: 'AWRaEscWMdvjVyaYlI-L',
    defaultColumns: ['json.hostname', 'json.pages_domain', 'json.host', 'json.pages_host', 'json.path', 'json.remote_ip', 'json.duration_ms'],
    defaultSeriesSplitField: 'json.pages_host.keyword',
    failureFilter: statusCode('json.status'),
    defaultLatencyField: 'json.duration_ms',
    latencyFieldUnitMultiplier: 1000,
  },

  postgres: indexDefaults {
    timestamp: '@timestamp',
    indexPattern: '97f04200-024b-11eb-81e5-155ba78758d4',
    defaultColumns: ['json.hostname', 'json.application_name', 'json.error_severity', 'json.message', 'json.session_start_time', 'json.sql_state_code', 'json.duration_ms'],
    defaultSeriesSplitField: 'json.sql_state_code',
    failureFilter: [mustNot(matchFilter('json.sql_state_code', '00000')), existsFilter('json.sql_state_code')],  // SQL Codes reference: https://www.postgresql.org/docs/9.4/errcodes-appendix.html
    defaultLatencyField: 'json.duration_ms',  // Only makes sense in the context of slowlog entries
    latencyFieldUnitMultiplier: 1000,
  },

  postgres_pgbouncer: indexDefaults {
    timestamp: 'json.time',
    indexPattern: '97f04200-024b-11eb-81e5-155ba78758d4',
    defaultColumns: ['json.hostname', 'json.pg_message'],
    defaultSeriesSplitField: 'json.hostname.keyword',
  },

  praefect: indexDefaults {
    timestamp: 'json.time',
    indexPattern: 'AW98WAQvqthdGjPJ8jTY',
    defaultColumns: ['json.hostname', 'json.virtual_storage', 'json.grpc.method', 'json.relative_path', 'json.grpc.code', 'json.grpc.time_ms'],
    defaultSeriesSplitField: 'json.grpc.method.keyword',
    failureFilter: [mustNot(matchFilter('json.grpc.code', 'OK')), existsFilter('json.grpc.code')],
    defaultLatencyField: 'json.grpc.time_ms',
    latencyFieldUnitMultiplier: 1000,
  },

  rails: indexDefaults {
    timestamp: 'json.time',
    indexPattern: 'AW5F1e45qthdGjPJueGO',
    defaultColumns: ['json.method', 'json.status', 'json.controller', 'json.action', 'json.path', 'json.duration_s'],
    defaultSeriesSplitField: 'json.controller.keyword',
    failureFilter: statusCode('json.status'),
    defaultLatencyField: 'json.duration_s',
    latencyFieldUnitMultiplier: 1,
  },

  rails_api: indexDefaults {
    timestamp: 'json.time',
    indexPattern: 'AW5F1e45qthdGjPJueGO',
    defaultColumns: ['json.method', 'json.status', 'json.route', 'json.path', 'json.duration_s'],
    defaultSeriesSplitField: 'json.route.keyword',
    failureFilter: statusCode('json.status'),
    defaultLatencyField: 'json.duration_s',
    latencyFieldUnitMultiplier: 1,
  },

  redis: indexDefaults {
    timestamp: 'json.time',
    indexPattern: 'AWSQX_Vf93rHTYrsexmk',
    defaultColumns: ['json.hostname', 'json.redis_message'],
    defaultSeriesSplitField: 'json.hostname.keyword',
    defaultLatencyField: 'json.exec_time',  // Note: this is only useful in the context of slowlogs
    latencyFieldUnitMultiplier: 1000000,  // Redis uses us
  },

  registry: indexDefaults {
    timestamp: 'json.time',
    indexPattern: '97ce8e90-63ad-11ea-8617-2347010d3aab',
    defaultColumns: ['json.http.request.uri', 'json.http.response.duration', 'json.err.code', 'json.msg', 'json.http.response.status', 'json.http.request.remoteaddr', 'json.http.request.method'],
    defaultSeriesSplitField: 'json.http.request.uri.keyword',
    failureFilter: statusCode('json.http.response.status'),
    // Requires https://gitlab.com/gitlab-com/gl-infra/infrastructure/-/issues/11136
    // defaultLatencyField: 'json.duration_s',
    // latencyFieldUnitMultiplier: 1,
  },

  runners: indexDefaults {
    timestamp: '@timestamp',
    indexPattern: 'AWgzayS3ENm-ja4G1a8d',
    defaultColumns: ['json.operation', 'json.job', 'json.operation', 'json.repo_url', 'json.project', 'json.msg'],
    defaultSeriesSplitField: 'json.repo_url.keyword',
    failureFilter: [matchFilter('json.msg', 'failed')],
    defaultLatencyField: 'json.duration',
    latencyFieldUnitMultiplier: 1000000000,  // nanoseconds, ah yeah
  },

  shell: indexDefaults {
    timestamp: 'json.time',
    indexPattern: 'AWORyp9K1NBBQZg_dXA9',
    defaultColumns: ['json.command', 'json.msg', 'json.level', 'json.gl_project_path', 'json.error'],
    defaultSeriesSplitField: 'json.gl_project_path.keyword',
    failureFilter: [matchFilter('json.level', 'error')],
  },

  sidekiq: indexDefaults {
    timestamp: 'json.time',
    indexPattern: 'AWNABDRwNDuQHTm2tH6l',
    defaultColumns: ['json.class', 'json.queue', 'json.meta.project', 'json.job_status', 'json.scheduling_latency_s', 'json.duration_s'],
    defaultSeriesSplitField: 'json.meta.project.keyword',
    failureFilter: [matchFilter('json.job_status', 'fail')],
    defaultLatencyField: 'json.duration_s',
    latencyFieldUnitMultiplier: 1,
  },

  workhorse: indexDefaults {
    timestamp: 'json.time',
    indexPattern: 'a4f5b470-edde-11ea-81e5-155ba78758d4',
    defaultColumns: ['json.method', 'json.remote_ip', 'json.status', 'json.uri', 'json.duration_ms'],
    defaultSeriesSplitField: 'json.remote_ip.keyword',
    failureFilter: statusCode('json.status'),
    defaultLatencyField: 'json.duration_ms',
    latencyFieldUnitMultiplier: 1000,
  },
};

local buildElasticDiscoverSearchQueryURL(index, filters, luceneQueries=[]) =
  local applicationState = {
    columns: indexCatalog[index].defaultColumns,
    filters: filters,
    index: indexCatalog[index].indexPattern,
    query: {
      language: 'kuery',
      query: std.join(' AND ', luceneQueries),
    },
  };

  indexCatalog[index].kibanaEndpoint + '#/discover?_a=' + rison.encode(applicationState) + grafanaTimeRange;

local buildElasticLineCountVizURL(index, filters, luceneQueries=[], splitSeries=false) =
  local ic = indexCatalog[index];

  local aggs =
    [
      {
        enabled: true,
        id: '1',
        params: {},
        schema: 'metric',
        type: 'count',
      },
      {
        enabled: true,
        id: '2',
        params: {
          drop_partials: true,
          extended_bounds: {},
          field: ic.timestamp,
          interval: 'auto',
          min_doc_count: 1,
          scaleMetricValues: false,
          timeRange: {
            from: grafanaTimeFrom,
            to: grafanaTimeTo,
          },
          useNormalizedEsInterval: true,
        },
        schema: 'segment',
        type: 'date_histogram',
      },
    ]
    +
    (
      if splitSeries then
        [{
          enabled: true,
          id: '3',
          params: {
            field: ic.defaultSeriesSplitField,
            missingBucket: false,
            missingBucketLabel: 'Missing',
            order: 'desc',
            orderBy: '1',
            otherBucket: true,
            otherBucketLabel: 'Other',
            size: 5,
          },
          schema: 'group',
          type: 'terms',
        }]
      else
        []
    );

  local applicationState = {
    filters: filters,
    query: {
      language: 'kuery',
      query: std.join(' AND ', luceneQueries),
    },
    vis: {
      aggs: aggs,
    },
  };

  indexCatalog[index].kibanaEndpoint + '#/visualize/create?type=line&indexPattern=' + indexCatalog[index].indexPattern + '&_a=' + rison.encode(applicationState) + grafanaTimeRange;

local buildElasticLineTotalDurationVizURL(index, filters, luceneQueries=[], latencyField, splitSeries=false) =
  local ic = indexCatalog[index];

  local aggs =
    [
      {
        enabled: true,
        id: '1',
        params: {
          field: latencyField,
        },
        schema: 'metric',
        type: 'sum',
      },
      {
        enabled: true,
        id: '2',
        params: {
          drop_partials: true,
          extended_bounds: {},
          field: ic.timestamp,
          interval: 'auto',
          min_doc_count: 1,
          scaleMetricValues: false,
          timeRange: {
            from: grafanaTimeFrom,
            to: grafanaTimeTo,
          },
          useNormalizedEsInterval: true,
        },
        schema: 'segment',
        type: 'date_histogram',
      },
    ]
    +
    (
      if splitSeries then
        [{
          enabled: true,
          id: '3',
          params: {
            field: ic.defaultSeriesSplitField,
            missingBucket: false,
            missingBucketLabel: 'Missing',
            order: 'desc',
            orderBy: '1',
            otherBucket: true,
            otherBucketLabel: 'Other',
            size: 5,
          },
          schema: 'group',
          type: 'terms',
        }]
      else
        []
    );

  local applicationState = {
    filters: filters,
    query: {
      language: 'kuery',
      query: std.join(' AND ', luceneQueries),
    },
    vis: {
      aggs: aggs,
      params: {
        valueAxes: [
          {
            id: 'ValueAxis-1',
            name: 'LeftAxis-1',
            position: 'left',
            scale: {
              mode: 'normal',
              type: 'linear',
            },
            show: true,
            style: {},
            title: {
              text: 'Sum Request Duration: ' + latencyField,
            },
            type: 'value',
          },
        ],
      },
    },
  };

  indexCatalog[index].kibanaEndpoint + '#/visualize/create?type=line&indexPattern=' + indexCatalog[index].indexPattern + '&_a=' + rison.encode(applicationState) + grafanaTimeRange;

local buildElasticLinePercentileVizURL(index, filters, luceneQueries=[], latencyField, splitSeries=false) =
  local ic = indexCatalog[index];

  local aggs =
    [
      {
        enabled: true,
        id: '1',
        params: {
          field: latencyField,
          percents: [
            95,
          ],
        },
        schema: 'metric',
        type: 'percentiles',
      },
      {
        enabled: true,
        id: '2',
        params: {
          drop_partials: true,
          extended_bounds: {},
          field: ic.timestamp,
          interval: 'auto',
          min_doc_count: 1,
          scaleMetricValues: false,
          timeRange: {
            from: grafanaTimeFrom,
            to: grafanaTimeTo,
          },
          useNormalizedEsInterval: true,
        },
        schema: 'segment',
        type: 'date_histogram',
      },
    ] +
    (
      if splitSeries then
        [
          {
            enabled: true,
            id: '3',
            params: {
              field: ic.defaultSeriesSplitField,
              missingBucket: false,
              missingBucketLabel: 'Missing',
              order: 'desc',
              orderAgg: {
                enabled: true,
                id: '3-orderAgg',
                params: {
                  field: latencyField,
                },
                schema: 'orderAgg',
                type: 'sum',
              },
              orderBy: 'custom',
              otherBucket: true,
              otherBucketLabel: 'Other',
              size: 5,
            },
            schema: 'group',
            type: 'terms',
          },
        ]
      else
        []
    );

  local applicationState = {
    filters: filters,
    query: {
      language: 'kuery',
      query: std.join(' AND ', luceneQueries),
    },
    vis: {
      aggs: aggs,
      params: {
        valueAxes: [
          {
            id: 'ValueAxis-1',
            name: 'LeftAxis-1',
            position: 'left',
            scale: {
              mode: 'normal',
              type: 'linear',
            },
            show: true,
            style: {},
            title: {
              text: 'p95 Request Duration: ' + latencyField,
            },
            type: 'value',
          },
        ],
      },
    },
  };

  indexCatalog[index].kibanaEndpoint + '#/visualize/create?type=line&indexPattern=' + indexCatalog[index].indexPattern + '&_a=' + rison.encode(applicationState) + grafanaTimeRange;

{
  matcher:: matcher,
  matchFilter:: matchFilter,
  rangeFilter:: rangeFilter,

  // Given an index, and a set of filters, returns a URL to a Kibana discover module/search
  buildElasticDiscoverSearchQueryURL(index, filters, luceneQueries=[])::
    buildElasticDiscoverSearchQueryURL(index, filters, luceneQueries),

  // Search for failed requests
  buildElasticDiscoverFailureSearchQueryURL(index, filters, luceneQueries=[])::
    buildElasticDiscoverSearchQueryURL(
      index,
      filters + indexCatalog[index].failureFilter,
      luceneQueries
    ),

  // Search for requests taking longer than the specified number of seconds
  buildElasticDiscoverSlowRequestSearchQueryURL(index, filters, luceneQueries=[], slowRequestSeconds)::
    local ic = indexCatalog[index];
    buildElasticDiscoverSearchQueryURL(
      index,
      filters + [rangeFilter(ic.defaultLatencyField, gteValue=slowRequestSeconds * ic.latencyFieldUnitMultiplier, lteValue=null)]
    ),

  // Given an index, and a set of filters, returns a URL to a Kibana count visualization
  buildElasticLineCountVizURL(index, filters, luceneQueries=[], splitSeries=false)::
    buildElasticLineCountVizURL(index, filters, luceneQueries, splitSeries=splitSeries),

  buildElasticLineFailureCountVizURL(index, filters, luceneQueries=[], splitSeries=false)::
    buildElasticLineCountVizURL(
      index,
      filters + indexCatalog[index].failureFilter,
      luceneQueries,
      splitSeries=splitSeries
    ),

  /**
   * Builds a total (sum) duration visualization. These queries are particularly useful for picking up
   * high volume short queries and can be useful in some types of incident investigations
   */
  buildElasticLineTotalDurationVizURL(index, filters, luceneQueries=[], field=null, splitSeries=false)::
    local fieldWithDefault = if field == null then
      indexCatalog[index].defaultLatencyField
    else
      field;
    buildElasticLineTotalDurationVizURL(index, filters, luceneQueries, fieldWithDefault, splitSeries=splitSeries),

  // Given an index, and a set of filters, returns a URL to a Kibana percentile visualization
  buildElasticLinePercentileVizURL(index, filters, luceneQueries=[], field=null, splitSeries=false)::
    local fieldWithDefault = if field == null then
      indexCatalog[index].defaultLatencyField
    else
      field;
    buildElasticLinePercentileVizURL(index, filters, luceneQueries, fieldWithDefault, splitSeries=splitSeries),

  // Returns true iff the named index supports failure queries
  indexSupportsFailureQueries(index)::
    std.objectHas(indexCatalog[index], 'failureFilter'),

  // Returns true iff the named index supports latency queries
  indexSupportsLatencyQueries(index)::
    std.objectHas(indexCatalog[index], 'defaultLatencyField'),

  /**
   * Best-effort converter for a prometheus selector hash,
   * to convert it into a ES matcher.
   * Returns an array of zero or more matchers.
   *
   * TODO: for now, only supports equal matches, improve this
   */
  getMatchersForPrometheusSelectorHash(index, selectorHash)::
    local prometheusLabelMappings = defaultPrometheusLabelMappings + indexCatalog[index].prometheusLabelMappings;

    std.flatMap(
      function(label)
        if std.objectHas(prometheusLabelMappings, label) then
          // A mapping from this prometheus label to a ES field exists
          if std.isString(selectorHash[label]) then  // TODO: improve this by expanding this to include eq, ne etc
            [matchFilter(prometheusLabelMappings[label], selectorHash[label])]
          else
            []
        else
          [],
      std.objectFields(selectorHash)
    ),
}
