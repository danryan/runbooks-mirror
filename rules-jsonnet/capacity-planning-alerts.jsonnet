local alerts = import 'alerts/alerts.libsonnet';
local elasticsearchLinks = import 'elasticlinkbuilder/elasticsearch_links.libsonnet';
local aggregations = import 'promql/aggregations.libsonnet';
local selectors = import 'promql/selectors.libsonnet';

local rules = {
  groups: [
    {
      name: 'capacity_planning_alerts',
      rules: [
        alerts.processAlertRule({
          alert: 'CapacityPlanningViolationForecast',
          expr: |||
            topk by (environment, type, tier, stage, shard, component) (1,
              tamland_forecast_violation_days{threshold_type="hard", confidence_type="80%"} >= 0
            )
          |||,
          'for': '1m',
          labels: {
            severity: 's4',
            alert_type: 'cause',
            incident_project: 'gitlab.com/gitlab-com/gl-infra/capacity-planning',
            link: 'https://gitlab-com.gitlab.io/gl-infra/tamland/{{ $labels.pagename }}.html#{{ $labels.type }}-service-{{ $labels.component }}-resource-saturation',
          },
          annotations: {
            title: '{{ $labels.type }} / {{ $labels.component }} potential saturation',
            description: |||
              Tamland forecast a potential future violation

              Report is available at <https://gitlab-com.gitlab.io/gl-infra/tamland/{{ $labels.pagename }}.html#{{ $labels.type }}-service-{{ $labels.component }}-resource-saturation>.
            |||,
          },
        }),
      ],
    },
  ],
};

{
  'capacity-planning-alerts.yml': std.manifestYamlDoc(rules),
}
