local periodicQuery = import './periodic-query.libsonnet';
local aggregations = import 'promql/aggregations.libsonnet';
local selectors = import 'promql/selectors.libsonnet';
local errorBudget = import 'stage-groups/error_budget.libsonnet';
local datetime = import 'utils/datetime.libsonnet';
local durationParser = import 'utils/duration-parser.libsonnet';
local budgetSeconds = (import 'stage-groups/error-budget/utils.libsonnet').budgetSeconds;

local selector = {
  environment: 'gprd',
  monitor: 'global',
};
local aggregationLabels = ['stage_group', 'product_stage'];
local now = std.extVar('current_time');
local midnight = datetime.new(now).beginningOfDay.toString;

local ratioQuery = |||
  max by (%(aggregations)s) (
    last_over_time(gitlab:stage_group:availability:ratio_28d{%(selector)s}[2h])
  )
||| % {
  aggregations: aggregations.join(aggregationLabels),
  selector: selectors.serializeHash(selector),
};

local trafficShareQuery = |||
  max by (%(aggregations)s) (
    last_over_time(gitlab:stage_group:traffic_share:ratio_28d{%(selector)s}[2h])
  )
||| % {
  aggregations: aggregations.join(aggregationLabels),
  selector: selectors.serializeHash(selector),
};

{
  stage_group_error_budget_availability: periodicQuery.new({
    requestParams: {
      query: ratioQuery,
      time: midnight,
    },
  }),

  stage_group_error_budget_seconds_spent: periodicQuery.new({
    requestParams: {
      query: |||
        (
          (
             1 - %(ratioQuery)s
          ) * %(rangeInSeconds)i
        )
      ||| % {
        ratioQuery: ratioQuery,
        rangeInSeconds: durationParser.toSeconds('28d'),
      },
      time: midnight,
    },
  }),

  stage_group_error_budget_seconds_remaining:
    local secondsSpent = self.stage_group_error_budget_seconds_spent;
    periodicQuery.new({
      requestParams: {
        query: |||
          %(budgetSeconds)i
          -
          %(timeSpentQuery)s
        ||| % {
          budgetSeconds: budgetSeconds(errorBudget().slaTarget, '28d'),
          timeSpentQuery: secondsSpent.requestParams.query,
        },
        time: midnight,
      },
    }),

  stage_group_traffic_share: periodicQuery.new({
    requestParams: {
      query: trafficShareQuery,
      time: midnight,
    },
  }),
}
