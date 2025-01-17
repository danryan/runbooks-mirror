local mappings = {
  camoproxy: import './index_mappings/camoproxy.jsonnet',
  consul: import './index_mappings/consul.jsonnet',
  gitaly: import './index_mappings/gitaly.jsonnet',
  gke: import './index_mappings/gke.jsonnet',
  kas: import './index_mappings/kas.jsonnet',
  mailroom: import './index_mappings/mailroom.jsonnet',
  mimir: import './index_mappings/mimir.jsonnet',
  mlops: import './index_mappings/mlops.jsonnet',
  monitoring: import './index_mappings/monitoring.jsonnet',
  observability: import './index_mappings/monitoring.jsonnet',
  packagecloud: import './index_mappings/packagecloud.jsonnet',
  pages: import './index_mappings/pages.jsonnet',
  postgres: import './index_mappings/postgres.jsonnet',
  praefect: import './index_mappings/praefect.jsonnet',
  pubsubbeat: import './index_mappings/pubsubbeat.jsonnet',
  puma: import './index_mappings/puma.jsonnet',
  rails: import './index_mappings/rails.jsonnet',
  redis: import './index_mappings/redis.jsonnet',
  registry: import './index_mappings/registry.jsonnet',
  runner: import './index_mappings/runner.jsonnet',
  sentry: import './index_mappings/sentry.jsonnet',
  shell: import './index_mappings/shell.jsonnet',
  sidekiq: import './index_mappings/sidekiq.jsonnet',
  system: import './index_mappings/system.jsonnet',
  vault: import './index_mappings/vault.jsonnet',
  workhorse: import './index_mappings/workhorse.jsonnet',
  zoekt: import './index_mappings/zoekt.jsonnet',
};
local settings = import 'settings_nonprod.libsonnet';

{
  get(
    index,
    env,
  ):: {
    index_patterns: ['pubsub-%s-inf-%s-*' % [index, env]],
    mappings: if std.objectHas(mappings, index) then mappings[index] else {},
    settings: settings.setting(index, env),
  },
}
