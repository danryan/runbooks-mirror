local selectors = import 'lib/selectors.libsonnet';

local globalSelector = { monitor: 'global' };
local nonGlobalSelector = { monitor: { nre: 'global|' } };

local formatConfigForSelectorHash(selectorHash) =
  {
    globalSelector: selectors.serializeHash(selectorHash + globalSelector + { env: selectorHash.environment }),
    selector: selectors.serializeHash(selectorHash + nonGlobalSelector),
  };

{
  apdex:: {
    serviceApdexQuery(selectorHash, range, worstCase=true)::
      if worstCase then
        /* Min apdex case */
        |||
          min by (type) (min_over_time(gitlab_service_apdex:ratio_5m{%(globalSelector)s}[%(range)s]))
          or
          min by (type) (min_over_time(gitlab_service_apdex:ratio{%(globalSelector)s}[%(range)s]))
        ||| % formatConfigForSelectorHash(selectorHash) { range: range }
      else
        /* Avg apdex case */
        |||
          avg by (type) (avg_over_time(gitlab_service_apdex:ratio_5m{%(globalSelector)s}[%(range)s]))
          or
          avg by (type) (avg_over_time(gitlab_service_apdex:ratio{%(globalSelector)s}[%(range)s]))
        ||| % formatConfigForSelectorHash(selectorHash) { range: range },

    serviceApdexDegradationSLOQuery(environmentSelectorHash, type, stage)::
      |||
        avg(slo:min:gitlab_service_apdex:ratio{%(selector)s}) or avg(slo:min:gitlab_service_apdex:ratio{type="%(type)s"})
      ||| % {
        selector: selectors.serializeHash(environmentSelectorHash { type: type, stage: stage }),
        type: type,
        stage: stage,
      },

    serviceApdexOutageSLOQuery(environmentSelectorHash, type, stage)::
      |||
        2 * (avg(slo:min:gitlab_service_apdex:ratio{%(selector)s}) or avg(slo:min:gitlab_service_apdex:ratio{type="%(type)s"})) - 1
      ||| % {
        selector: selectors.serializeHash(environmentSelectorHash { type: type, stage: stage }),
        type: type,
        stage: stage,
      },

    serviceApdexQueryWithOffset(selectorHash, offset)::
      |||
        min by (type) (gitlab_service_apdex:ratio_5m{%(globalSelector)s} offset %(offset)s)
        or
        min by (type) (gitlab_service_apdex:ratio{%(globalSelector)s} offset %(offset)s)
      ||| % formatConfigForSelectorHash(selectorHash) { offset: offset },

    componentApdexQuery(selectorHash, range)::
      |||
        sum by (component, type) (
          (avg_over_time(gitlab_component_apdex:ratio_5m{%(selector)s}[%(range)s]) >= 0)
          *
          (gitlab_component_apdex:weight:score_5m{%(selector)s} >= 0)
        )
        /
        sum by (component, type) (
          (gitlab_component_apdex:weight:score_5m{%(selector)s} >= 0)
        )
      ||| % formatConfigForSelectorHash(selectorHash) { range: range },
  },

  opsRate:: {
    serviceOpsRateQuery(selectorHash, range)::
      |||
        avg by (type)
        (avg_over_time(gitlab_service_ops:rate_5m{%(globalSelector)s}[%(range)s]))
        or
        sum by (type) (gitlab_service_ops:rate_5m{%(selector)s})
      ||| % formatConfigForSelectorHash(selectorHash) { range: range },

    serviceOpsRateQueryWithOffset(selectorHash, offset)::
      |||
        avg by (type) (
          gitlab_service_ops:rate_5m{%(globalSelector)s} offset %(offset)s
        )
        or
        sum by (type) (
          gitlab_service_ops:rate_5m{%(selector)s} offset %(offset)s
        )
      ||| % formatConfigForSelectorHash(selectorHash) { offset: offset },

    serviceOpsRatePrediction(selectorHash, sigma)::
      |||
        clamp_min(
          avg by (type) (
            gitlab_service_ops:rate:prediction{%(globalSelector)s}
            + (%(sigma)g) *
            gitlab_service_ops:rate:stddev_over_time_1w{%(globalSelector)s}
          )
          or
          (
              sum by (type) (gitlab_service_ops:rate:prediction{%(selector)s})
              + (%(sigma)g) *
              sum by (type) (gitlab_service_ops:rate:stddev_over_time_1w{%(selector)s})
          ),
          0
        )
      ||| % formatConfigForSelectorHash(selectorHash) { sigma: sigma },

    componentOpsRateQuery(selectorHash, range)::
      |||
        sum(
          avg_over_time(
            gitlab_component_ops:rate_5m{%(selector)s}[%(range)s]
          )
        ) by (component)
      ||| % formatConfigForSelectorHash(selectorHash) { range: range },
  },

  errorRate:: {
    serviceErrorRateQuery(selectorHash, range, clampMax=1.0, worstCase=true)::
      if worstCase then
        /* Max case */
        |||
          clamp_max(
            max by (type) (max_over_time(gitlab_service_errors:ratio_5m{%(globalSelector)s}[$__interval]))
            or
            sum by (type) (gitlab_service_errors:ratio_5m{%(selector)s}),
            %(clampMax)g
          )
        ||| % formatConfigForSelectorHash(selectorHash) { range: range, clampMax: clampMax }
      else
        /* Avg case */
        |||
          clamp_max(
            avg by (type) (avg_over_time(gitlab_service_errors:ratio_5m{%(globalSelector)s}[$__interval])),
            %(clampMax)g
          )
        ||| % formatConfigForSelectorHash(selectorHash) { range: range, clampMax: clampMax },

    serviceErrorRateDegradationSLOQuery(environmentSelectorHash, type, stage)::
      |||
        avg(slo:max:gitlab_service_errors:ratio{%(selector)s}) or avg(slo:max:gitlab_service_errors:ratio{type="%(type)s"})
      ||| % {
        selector: selectors.serializeHash(environmentSelectorHash { type: type, stage: stage }),
        type: type,
        stage: stage,
      },

    serviceErrorRateOutageSLOQuery(environmentSelectorHash, type, stage)::
      |||
        2 * (avg(slo:max:gitlab_service_errors:ratio{%(selector)s}) or avg(slo:max:gitlab_service_errors:ratio{type="%(type)s"}))
      ||| % {
        selector: selectors.serializeHash(environmentSelectorHash { type: type, stage: stage }),
        type: type,
        stage: stage,
      },

    serviceErrorRateQueryWithOffset(selectorHash, offset)::
      |||
        max by (type) (gitlab_service_errors:ratio_5m{%(globalSelector)s} offset %(offset)s)
        or
        sum by (type) (gitlab_service_errors:ratio_5m{%(selector)s} offset %(offset)s)
      ||| % formatConfigForSelectorHash(selectorHash) { offset: offset },

    componentErrorRateQuery(selectorHash)::
      |||
        sum(
          gitlab_component_errors:rate_5m{%(selector)s}
        ) by (component)
        /
        sum(
          gitlab_component_ops:rate_5m{%(selector)s}
        ) by (component)
      ||| % formatConfigForSelectorHash(selectorHash) {},
  },
}
