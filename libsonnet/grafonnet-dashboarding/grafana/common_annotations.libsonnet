local g = import 'grafonnet-dashboarding/grafana/g.libsonnet';
local annotation = g.dashboard.annotation;

// The constructor for the old grafonnet-lib implementation looks like this:
// datasource(
//   name,
//   datasource,
//   expr=null,
//   enable=true,
//   hide=false,
//   iconColor='rgba(255, 96, 96, 1)',
//   tags=[],
//   type='tags',
//   builtIn=null,
// )::

local defaultGrafanaAnnotation = annotation.withDatasource('-- Grafana --')
                                 + annotation.withEnable(false)
                                 + annotation.withBuiltIn(1);

{
  deploymentsForEnvironment::
    defaultGrafanaAnnotation
    + annotation.withName('deploy')
    + annotation.target.withTags(['deploy', '$environment'])
    + annotation.withIconColor('#96D98D')
    + annotation.withEnable(true),

  deploymentsForEnvironmentCny::
    defaultGrafanaAnnotation
    + annotation.withName('deploy')
    + annotation.target.withTags(['deploy', '${environment}-cny'])
    + annotation.withIconColor('#FFEE52'),

  featureFlags::
    defaultGrafanaAnnotation
    + annotation.withName('feature-flags')
    + annotation.target.withTags(['feature-flag', '$environment'])
    + annotation.withIconColor('#FFEE52'),

  standardEnvironmentAnnotations: [self.deploymentsForEnvironment, self.deploymentsForEnvironmentCny, self.featureFlags],

  deploymentsForRunway(service='${type}')::
    defaultGrafanaAnnotation
    + annotation.withName('runway-deploy')
    + annotation.withEnable(true)
    + annotation.target.withTags(['platform:runway', 'service:' + service, 'env:${environment}'])
    + annotation.withIconColor('#fda324'),
}
