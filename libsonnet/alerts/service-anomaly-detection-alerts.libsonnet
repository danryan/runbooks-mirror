local selectors = import 'promql/selectors.libsonnet';
local stableIds = import 'stable-ids/stable-ids.libsonnet';

local rules = function(extraSelector, tenant=null)
  local selector = { monitor: 'global' } + extraSelector;
  [
    //###############################################
    // Operation Rate: how many operations is this service handling per second?
    //###############################################
    // ------------------------------------
    // Upper bound thresholds exceeded
    // ------------------------------------
    // Warn: Operation rate above 2 sigma
    {
      alert: 'service_ops_out_of_bounds_upper_5m',
      // gitlab_service:mapping rules are still recorded across environments
      // They apply to all environments
      expr: |||
        (
            (
              (gitlab_service_ops:rate_5m{%(selector)s} -  gitlab_service_ops:rate:prediction{%(selector)s}) /
            gitlab_service_ops:rate:stddev_over_time_1w{%(selector)s}
          )
          >
          3
        )
        unless on(tier, type)
        gitlab_service:mapping:disable_ops_rate_prediction{monitor="global"}
      ||| % {
        selector: selectors.serializeHash(selector),
      },
      'for': '5m',
      labels: {
        rules_domain: 'general',
        severity: 's4',
        alert_type: 'cause',
      },
      annotations: {
        description: |||
          The `{{ $labels.type }}` service (`{{ $labels.stage }}` stage) is receiving more requests than normal.
          This is often caused by user generated traffic, sometimes abuse. It can also be cause by application changes that lead to higher operations rates or from retries in the event of errors. Check the abuse reporting watches in Elastic, ELK for possible abuse, error rates (possibly on upstream services) for root cause.
        |||,
        runbook: 'docs/{{ $labels.type }}/README.md',
        title: 'Anomaly detection: The `{{ $labels.type }}` service (`{{ $labels.stage }}` stage) is receiving more requests than normal',
        grafana_dashboard_id: 'general-service/service-platform-metrics',
        grafana_panel_id: stableIds.hashStableId('service-$type-ops-rate'),
        grafana_variables: 'environment,type,stage',
        grafana_min_zoom_hours: '12',
        grafana_datasource_id: tenant,
        link1_title: 'Definition',
        link1_url: 'https://gitlab.com/gitlab-com/runbooks/blob/master/docs/monitoring/definition-service-ops-rate.md',
        promql_template_1: 'gitlab_service_ops:rate{environment="$environment", type="$type", stage="$stage"}',
        promql_template_2: 'gitlab_component_ops:rate{environment="$environment", type="$type", stage="$stage"}',
      },
    },
    // ------------------------------------
    // Lower bound thresholds exceeded
    // ------------------------------------
    // Warn: Operation rate below 2 sigma
    {
      alert: 'service_ops_out_of_bounds_lower_5m',
      expr: |||
        (
            (
              (gitlab_service_ops:rate_5m{%(selector)s} -  gitlab_service_ops:rate:prediction{%(selector)s}) /
            gitlab_service_ops:rate:stddev_over_time_1w{%(selector)s}
          )
          <
          -3
        )
        unless on(tier, type)
        gitlab_service:mapping:disable_ops_rate_prediction{monitor="global"}
      ||| % {
        selector: selectors.serializeHash(selector),
      },
      'for': '5m',
      labels: {
        rules_domain: 'general',
        severity: 's4',
        alert_type: 'cause',
      },
      annotations: {
        description: |||
          The `{{ $labels.type }}` service (`{{ $labels.stage }}` stage) is receiving fewer requests than normal.
          This is often caused by a failure in an upstream service - for example, an upstream load balancer rejected all incoming traffic. In many cases, this is as serious or more serious than a traffic spike. Check upstream services for errors that may be leading to traffic flow issues in downstream services.
        |||,
        runbook: 'docs/{{ $labels.type }}/README.md',
        title: 'Anomaly detection: The `{{ $labels.type }}` service (`{{ $labels.stage }}` stage) is receiving fewer requests than normal',
        grafana_dashboard_id: 'general-service/service-platform-metrics',
        grafana_panel_id: stableIds.hashStableId('service-$type-ops-rate'),
        grafana_variables: 'environment,type,stage',
        grafana_min_zoom_hours: '12',
        grafana_datasource_id: tenant,
        link1_title: 'Definition',
        link1_url: 'https://gitlab.com/gitlab-com/runbooks/blob/master/docs/monitoring/definition-service-ops-rate.md',
        promql_template_1: 'gitlab_service_ops:rate{environment="$environment", type="$type", stage="$stage"}',
        promql_template_2: 'gitlab_component_ops:rate{environment="$environment", type="$type", stage="$stage"}',
      },
    },
  ];

rules
