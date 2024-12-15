local metricsCatalog = import 'servicemetrics/metrics-catalog.libsonnet';
local services = (import 'gitlab-metrics-config.libsonnet').monitoredServices;
local misc = import 'utils/misc.libsonnet';
local selectors = import 'promql/selectors.libsonnet';

// Outputs:
// {
//   "redis": {
//     "slis": {
//       "primary_server": {
//         "apdex": [],
//         "errorRate": [],
//         "requestRate": [
//           {
//             "metric": "redis_commands_processed_total",
//             "raw": "redis_commands_processed_total{type=\"redis\"}",
//             "selector": {
//               "type": "redis"
//             }
//           }
//         ]
//       },
//       "rails_redis_client": {
//         "apdex": [
//           {
//             "metric": "gitlab_redis_client_requests_duration_seconds_bucket",
//             "raw": "gitlab_redis_client_requests_duration_seconds_bucket{storage=\"shared_state\",type!=\"ops-gitlab-net\"}",
//             "selector": {
//               "storage": "shared_state",
//               "type": {
//                 "ne": "ops-gitlab-net"
//               }
//             }
//           }
//         ],
//         "errorRate": [
//           {
//             "metric": "gitlab_redis_client_exceptions_total",
//             "raw": "gitlab_redis_client_exceptions_total{storage=\"shared_state\",type!=\"ops-gitlab-net\"}",
//             "selector": {
//               "storage": "shared_state",
//               "type": {
//                 "ne": "ops-gitlab-net"
//               }
//             }
//           }
//         ],
//         "requestRate": [
//           {
//             "metric": "gitlab_redis_client_requests_total",
//             "raw": "gitlab_redis_client_requests_total{storage=\"shared_state\",type!=\"ops-gitlab-net\"}",
//             "selector": {
//               "storage": "shared_state",
//               "type": {
//                 "ne": "ops-gitlab-net"
//               }
//             }
//           }
//         ]
//       },
//       "secondary_servers": {
//         "apdex": [],
//         "errorRate": [],
//         "requestRate": [
//           {
//             "metric": "redis_commands_processed_total",
//             "raw": "redis_commands_processed_total{type=\"redis\"}",
//             "selector": {
//               "type": "redis"
//             }
//           }
//         ]
//       }
//     }
//   }
// }

local generateApdex(sli) =
  // ignore combined SLI
  local result = if std.objectHas(sli, 'components') then
    []
  else
    if sli.hasHistogramApdex() then
      if std.objectHas(sli.apdex, 'metrics') then
        [
          {
            metric: metric.histogram,
            selector: metric.selector,
            raw: self.metric + selectors.serializeHash(self.selector, withBraces=true),
          }
          for metric in sli.apdex.metrics
        ]
      else
        [{
          metric: sli.apdex.histogram,
          selector: sli.apdex.selector,
        }]
    else
      if sli.hasApdex() then
        local metric = if misc.digHas(sli, ['apdex', 'errorRateMetric']) then
          sli.apdex.errorRateMetric
        else if misc.digHas(sli, ['apdex', 'successRateMetric']) then
          sli.apdex.successRateMetric;

        [{
          metric: metric,
          selector: sli.apdex.selector,
        }]
      else
        [];

  std.map(
    function(obj)
      obj { raw: obj.metric + selectors.serializeHash(obj.selector, withBraces=true) },
    result
  );

local singleRequestRate(sli, type) =
  local result = if std.objectHas(sli[type], 'counter') then
    [
      {
        metric: sli[type].counter,
        selector: sli[type].selector,
      },
    ]
  else if std.objectHas(sli[type], 'gauge') then
    [
      {
        metric: sli[type].gauge,
        selector: sli[type].selector,
      },
    ];

  std.map(
    function(obj)
      obj { raw: obj.metric + selectors.serializeHash(obj.selector, withBraces=true) },
    result
  );

local generateRate(sli, type) =
  // TODO: ignore combined SLI
  local result = if std.objectHas(sli, 'components') then
    []
  else if !std.objectHas(sli, type) then
    []
  else
    if std.objectHas(sli[type], 'counter') || std.objectHas(sli[type], 'gauge') then
      singleRequestRate(sli, type)
    else if std.objectHas(sli[type], 'metrics') then
      [
        {
          metric: metric.counter,
          selector: metric.selector,
        }
        for metric in sli[type].metrics
      ]
    else
      // ignore custom rate query
      [];

  std.map(
    function(obj)
      obj { raw: obj.metric + selectors.serializeHash(obj.selector, withBraces=true) },
    result
  );

local getSlisAndSelectors(service) =
  {
    [sli.name]: {
      apdex: generateApdex(sli),
      requestRate: generateRate(sli, 'requestRate'),
      errorRate: generateRate(sli, 'errorRate'),
    }
    for sli in service.listServiceLevelIndicators()
  };

{
  [service.type]: {
    serviceDependencies: std.get(service, 'serviceDependencies'),
    slis: getSlisAndSelectors(service),
  }
  for service in services
}
