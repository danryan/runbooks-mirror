local alerts = import 'alerts/alerts.libsonnet';
local selectors = import 'promql/selectors.libsonnet';

function(tenant, selector)
  {
    local envSelector = selectors.serializeHash(selector),
    groups: [
      {
        name: 'gitlab-pg-table-sizes.rules',
        rules: [
          {
            record: 'gitlab_com:top_50_pg_total_relation_size_bytes',
            expr: |||
              topk(50, avg by (schemaname, relname) ((avg_over_time(pg_total_relation_size_bytes{env="gprd",type="patroni"}[1h]) < (0.5*50*2^30) and on (job, instance) (pg_replication_is_replica{env="gprd",type="patroni"} == 0)))) / (50*2^30)
            ||| % { selector: envSelector },
          },

          // pgTableSizesTooLarge
          alerts.processAlertRule({
            alert: 'pgTableSizesTooLarge',
            expr: '(gitlab_com:top_50_pg_total_relation_size_bytes{type!="patroni-embedding",  %(selector)s} >= 60 * 15) or (gitlab_com:last_walg_backup_age_in_seconds{type="patroni-embedding", %(selector)s} >= 60 * 60)' % { selector: envSelector },
            'for': '5m',
            labels: {
              severity: 's3',
              alert_type: 'symptom',
              incident_project: 'gitlab.com/gitlab-com/gl-infra/production',
            },
            annotations: {
              title: 'Table size for "{{ $value }}" is exceeding the authorized limit for env "{{ $labels.environment }}".',
              description: 'The table size for this table is too large please reduce it in order to avoid future problems. https://docs.gitlab.com/ee/development/database/large_tables_limitations.html',
              grafana_min_zoom_hours: '4',
              grafana_variables: 'environment',
              grafana_datasource_id: tenant,
            },
          }),
        ],
      },
    ],
  }
