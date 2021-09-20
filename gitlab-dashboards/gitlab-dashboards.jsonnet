local services = (import 'gitlab-metrics-config.libsonnet').monitoredServices;

local generateDashboardForService(service) =
  local type = service.type;
  local formatConfig = { type: type };

  {
    dashboard: 'Key Services -  %(type)s' % formatConfig,
    panel_groups: [
      {
        group: 'Key Services - %(type)s' % formatConfig,
        panels: [
          {
            title: 'Latency: Apdex',
            type: 'line-chart',
            y_label: 'Apdex %',
            metrics: [
              {
                id: 'line-chart-latency-apdex-%(type)s-service' % formatConfig,
                query_range: 'avg(gitlab_service_apdex:ratio_5m{environment="gprd", type="%(type)s", stage="main"}) by (type)' % formatConfig,
                unit: '%',
                label: '{{type}} Service' % formatConfig,
              },
            ],
          },
          {
            title: 'Error Ratios',
            type: 'line-chart',
            y_label: '% Requests in Error',
            metrics: [
              {
                id: 'line-chart-%(type)s-service-error-ratios' % formatConfig,
                query_range: 'avg(gitlab_service_errors:ratio_5m{environment="gprd", type="%(type)s", stage="main"}) by (type)' % formatConfig,
                unit: '%',
                label: '{{type}} Service' % formatConfig,
              },
            ],
          },
          {
            title: 'RPS - Service Requests per Second',
            type: 'anomaly-chart',
            y_label: 'Operations per Second',
            metrics: [
              {
                id: 'line_chart_rps_%(type)s_service_normal' % formatConfig,
                query_range: 'sum(gitlab_service_ops:rate_5m{environment="gprd", type="%(type)s", stage="main"}) by (type)' % formatConfig,
                unit: '%',
                label: '{{type}} service',
              },
              {
                id: 'line_chart_rps_%(type)s_service_upper_limit' % formatConfig,
                query_range: 'gitlab_service_ops:rate:prediction{environment="gprd", type="%(type)s", stage="main"} + 3 * gitlab_service_ops:rate:stddev_over_time_1w{environment="gprd", type="%(type)s", stage="main"}' % formatConfig,
                unit: '%',
                label: 'upper limit',
              },
              // TODO: Change this back to multiline YAML strings once: https://gitlab.com/gitlab-org/gitlab/issues/208218 has been resolved
              {
                id: 'line_chart_rps_%(type)s_service_lower_limit' % formatConfig,
                query_range: 'gitlab_service_ops:rate:prediction{environment="gprd", type="%(type)s", stage="main"} - 3 * gitlab_service_ops:rate:stddev_over_time_1w{environment="gprd", type="%(type)s", stage="main"}' % formatConfig,
                unit: '%',
                label: 'lower limit',
              },
            ],
          },
          {
            title: 'Saturation',
            type: 'line-chart',
            y_label: 'Saturation %',
            metrics: [
              {
                id: 'line-chart-%(type)s-service-cpu-component-saturation' % formatConfig,
                query_range: 'max(max_over_time(gitlab_component_saturation:ratio{environment="gprd", type="%(type)s", stage="main"}[1m])) by (component)' % formatConfig,
                unit: '%',
                label: 'component',
              },
            ],
          },
        ],
      },
    ],
  };

local outputDashboardYaml(service) =
  std.manifestYamlDoc(generateDashboardForService(service));

{
  ['key-metrics-%s.yml' % [service.type]]:
    outputDashboardYaml(service)
  for service in services
}
