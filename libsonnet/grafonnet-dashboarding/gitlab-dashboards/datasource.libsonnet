local config = import 'gitlab-metrics-config.libsonnet';

{
  defaultDatasourceForService(service)::
    if service.defaultTenant != null then
      // NOTE: Mimir datasource is only available for GitLab.com,
      // not applicable for GET-hybrid environments.
      local mimirHelpers = import 'services/lib/mimir-helpers.libsonnet';
      mimirHelpers.mimirDatasource(service.defaultTenant)
    else
      config.defaultPrometheusDatasource,
}
