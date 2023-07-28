local schedule_mins = 15;  // Run this watch at this frequency, in minutes
local query_period = schedule_mins + 2;
local alert_threshold = 5;

local es_query = {
  search_type: 'query_then_fetch',
  indices: [
    'pubsub-rails-inf-gprd-*',
    'pubsub-sidekiq-inf-gprd-*',
  ],
  rest_total_hits_as_int: true,
  body: {
    query: {
      bool: {
        must: [
          {
            range: {
              '@timestamp': {
                gte: std.format('now-%dm', query_period),
                lte: 'now',
              },
            },
          },
          {
            match_phrase: {
              'json.message': '[BUG] Segmentation fault',
            },
          },
        ],
      },
    },
    size: 0,
  },
};

{
  trigger: {
    schedule: {
      interval: std.format('%dm', schedule_mins),
    },
  },
  input: {
    search: {
      request: es_query,
    },
  },
  condition: {
    compare: {
      'ctx.payload.hits.total': {
        gt: alert_threshold,
      },
    },
  },
  actions: {
    'notify-slack': {
      throttle_period: query_period + 'm',
      slack: {
        message: {
          from: 'ElasticCloud Watcher: High RateLimitError Rate',
          to: [
            '#ai_vulnerability_explanation',
          ],
          text: 'RateLimitError: {{ctx.payload.hits.total}} errors detected! This may mean the AI integration is down.',
          attachments: [
            {
              title: ':spiral_note_pad: RateLimitErrors in Rails logs:',
              text: 'https://log.gprd.gitlab.net/goto/3670f880-8913-11ec-9dd2-93d354bef8e7',
            },
            {
              title: ':spiral_note_pad: RateLimitErrors in Sidekiq logs:',
              text: 'https://log.gprd.gitlab.net/goto/47a54480-8913-11ec-9dd2-93d354bef8e7',
            },
            {
              title: ':runbooks: Runbook:',
              # text: 'https://gitlab.com/gitlab-com/runbooks/-/blob/master/docs/uncategorized/staging-environment.md#elasticcloud-watcher-segmentation-faults',
            },
          ],
        },
      },
    },
  },
}
