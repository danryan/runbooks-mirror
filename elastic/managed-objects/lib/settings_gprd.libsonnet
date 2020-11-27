local HIGH_THROUHGPUT = ['gitaly', 'rails', 'workhorse', 'gke-systemd'];
local MEDIUM_THROUGHPUT = ['gke-audit', 'shell', 'sidekiq', 'system'];

local setting(index, env) = if std.member(HIGH_THROUHGPUT, index) then {
  index: {
    lifecycle: {
      name: 'gitlab-infra-high-ilm-policy',
      rollover_alias: 'pubsub-%s-inf-%s' % [index, env],
    },
    mapping: {
      ignore_malformed: true,
      total_fields: {
        limit: 10000,
      },
    },
    routing: {
      allocation: {
        total_shards_per_node: 1,
      },
    },
    search: {
      idle: {
        after: '30s',
      },
    },
    refresh_interval: '20s',  // see: https://gitlab.com/gitlab-com/gl-infra/production/-/issues/3006#note_445081437
  },
  number_of_shards: 5,
  // number_of_replicas: 1,
}
else if std.member(MEDIUM_THROUGHPUT, index) then {
  index: {
    lifecycle: {
      name: 'gitlab-infra-medium-ilm-policy',
      rollover_alias: 'pubsub-%s-inf-%s' % [index, env],
    },
    mapping: {
      ignore_malformed: true,
    },
    routing: {
      allocation: {
        total_shards_per_node: 1,
      },
    },
    search: {
      idle: {
        after: '30s',
      },
    },
    refresh_interval: '20s',
  },
  number_of_shards: 3,
  // number_of_replicas: 1,
} else {
  index: {
    lifecycle: {
      name: 'gitlab-infra-default-ilm-policy',
      rollover_alias: 'pubsub-%s-inf-%s' % [index, env],
    },
    mapping: {
      ignore_malformed: true,
    },
    search: {
      idle: {
        after: '30s',
      },
    },
    refresh_interval: '20s',
  },
  // number_of_shards: 1,
  // number_of_replicas: 1,
};

{
  setting:: setting,
}
