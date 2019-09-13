local TRIGGER_SCHEDULE_HOURS = 24;  // Run this watcher once a day

local P95_THRESHOLD_MILLIS = 10000;  // Minimum p95 on which to report

local query() = {
  search_type: 'query_then_fetch',
  indices: [
    'pubsub-rails-inf-gprd*',
  ],
  types: [],
  body: {
    query: {
      bool: {
        must: [{
          range: {
            "@timestamp": {
              gte: std.format('now-%dh', TRIGGER_SCHEDULE_HOURS),
              lte: "now",
            },
          },
        }],
      },
    },
    size: 0,

    aggs: {
      controller: {
        terms: {
          field: "json.controller.keyword",
          size: 50,
          order: {
            sum_duration: "desc",
          },
        },
        aggs: {
          sum_duration: {
            sum: {
              field: "json.duration",
            },
          },
          action: {
            terms: {
              field: "json.action.keyword",
              size: 5,
              order: {
                sum_duration: "desc",
              },
            },
            aggs: {
              sum_duration: {
                sum: {
                  field: "json.duration",
                },
              },
              percentile_durations: {
                percentiles: {
                  field: "json.duration",
                  percents: [95],
                  keyed: false,
                },
              },
            },
          },
        },
      },
    },
  },
};

local painlessFunctions = "
  boolean findAction(def actionBucket, def params) {
    actionBucket.percentile_durations.values[0].value >= params.P95_THRESHOLD_MILLIS
  }

  boolean findController(def controllerBucket, def params) {
    controllerBucket.action.buckets.any(actionBucket -> findAction(actionBucket, params))
  }

  Object collectActions(def controllerBucket, def params) {
    controllerBucket.action.buckets.findAll(actionBucket -> findAction(actionBucket, params)).collect(actionBucket -> [
      'action': actionBucket,
      'actionKey': actionBucket.key,
      'p95latencySeconds': Math.round(actionBucket.percentile_durations.values[0].value/1000),
      'controller':controllerBucket.key
    ])
  }
";

local conditionScript = "
  ctx.payload.aggregations.controller.buckets.any(controllerBucket -> findController(controllerBucket, params))
";

local transformScript = "
  [
    'items': ctx.payload.aggregations.controller.buckets.collect(controllerBucket -> collectActions(controllerBucket, params))
      .stream()
      .flatMap(x -> x.stream())
      .collect(Collectors.toList())
  ]
";

local painlessScript(script) = {
  script: {
    inline: painlessFunctions + "\n" + script,
    lang: "painless",
    params: {
      P95_THRESHOLD_MILLIS: P95_THRESHOLD_MILLIS,
    },
  },
};

local searchLinkTemplate() =
  "https://log.gitlab.net/app/kibana#/discover?_g=(refreshInterval:(display:Off,pause:!f,value:0),time:(from:now-24h,mode:quick,to:now))&_a=(columns:!(json.controller,json.action,json.duration,json.path,json.status),filters:!(('$state':(store:appState),meta:(alias:!n,disabled:!f,index:AWOSvARQwig0Nc2UGcr2,key:json.controller,negate:!f,type:phrase,value:'{{controller}}'),query:(match:(json.controller:(query:'{{controller}}',type:phrase)))),('$state':(store:appState),meta:(alias:!n,disabled:!f,index:AWOSvARQwig0Nc2UGcr2,key:json.action,negate:!f,type:phrase,value:'{{actionKey}}'),query:(match:(json.action:(query:'{{actionKey}}',type:phrase))))),index:AWOSvARQwig0Nc2UGcr2,interval:auto,query:(match_all:()),sort:!(json.duration,desc))";

{
  trigger: {
    schedule: {
      interval: std.format('%dh', TRIGGER_SCHEDULE_HOURS),
    },
  },
  input: {
    search: {
      request: query(),
    },
  },
  condition: painlessScript(conditionScript),
  transform: painlessScript(transformScript),
  actions: {
    "notify-slack": {
      slack: {
        account: "gitlab_team",
        message: {
          from: "ElasticCloud Watcher: worst-case p95",
          to: [
            "#mech_symp_alerts",
          ],
          text: "*Worst performing Rails controllers in the applications, by p95 latency*
Click through to find events...",
          dynamic_attachments: {
            list_path: "ctx.payload.items",
            attachment_template: {
              title: "{{controller}}#{{actionKey}}",
              title_link: searchLinkTemplate(),
              text: "p95 latency for this endpoint: {{ p95latencySeconds }}s",
            },
          },
        },
      },
    },
  },
}
