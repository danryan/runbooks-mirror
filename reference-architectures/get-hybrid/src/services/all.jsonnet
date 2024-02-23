local gitlabMetricsConfig = (import 'gitlab-metrics-config.libsonnet');

local all =
  [
    import 'consul.jsonnet',
    import 'gitaly.jsonnet',
    import 'gitlab-shell.jsonnet',
    import 'registry.jsonnet',
    import 'sidekiq.jsonnet',
    import 'webservice.jsonnet',
  ] + (
    if gitlabMetricsConfig.options.elasticacheMonitoring then
      [import 'aws-elasticache.jsonnet']
    else
      []
  ) + (
    if gitlabMetricsConfig.options.rdsMonitoring then
      [import 'aws-rds.jsonnet']
    else
      []
  ) + (
    if gitlabMetricsConfig.options.praefect.enable then
      [import 'praefect.jsonnet']
    else
      []
  ) +
  std.get(gitlabMetricsConfig.options, 'services', []);

// Sort services
std.sort(all, function(f) f.type)
