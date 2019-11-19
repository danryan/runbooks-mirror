local TRIGGER_SCHEDULE_MINS = 5;  // Run this watcher at this frequency, in minutes
local QUERY_PERIOD_MINS = 120;
local ALERT_THRESHOLD = 0;

local ES_QUERY = {
  search_type: 'query_then_fetch',
  indices: [
    'pubsub-rails-inf-gstg-*',
  ],
  types: [],
  body: {
    size: 0,
    query: {
      bool: {
        must: [
          { match_phrase: { 'json.message': { query: 'redacted_search_results' } } },
          { range: { '@timestamp': { gte: std.format('now-%dm', QUERY_PERIOD_MINS), lte: 'now' } } },
        ],
      },
    },
  },
};


{
  trigger: {
    schedule: {
      interval: std.format('%dm', TRIGGER_SCHEDULE_MINS),
    },
  },
  input: {
    search: {
      request: ES_QUERY,
    },
  },
  condition: {
    compare: {
      'ctx.payload.hits.total.value': {
        gt: ALERT_THRESHOLD,
      },
    },
  },
  actions: {
    'notify-slack': {
      throttle_period: '30m',
      slack: {
        account: 'gitlab_team',
        message: {
          from: 'ElasticCloud Watcher: es_integration_redacted_results',
          to: [
            '#sec-appsec-private',
          ],
          text: 'Search results from the ES integration in gstg environment were redacted. Visit https://nonprod-log.gitlab.net/goto/84600aa0711d38da1a309befa091470b for more details',
        },
      },
    },
  },
}
