local saturationTypes = [
  import 'cgroup_memory.libsonnet',
  import 'cpu.libsonnet',
  import 'disk_inodes.libsonnet',
  import 'disk_space.libsonnet',
  import 'disk_sustained_read_iops.libsonnet',
  import 'disk_sustained_read_throughput.libsonnet',
  import 'disk_sustained_write_iops.libsonnet',
  import 'disk_sustained_write_throughput.libsonnet',
  import 'elastic_cpu.libsonnet',
  import 'elastic_disk_space.libsonnet',
  import 'elastic_jvm_heap_memory.libsonnet',
  import 'elastic_single_node_cpu.libsonnet',
  import 'elastic_single_node_disk_space.libsonnet',
  import 'elastic_thread_pools.libsonnet',
  import 'go_memory.libsonnet',
  import 'kube_container_cpu.libsonnet',
  import 'kube_container_memory.libsonnet',
  import 'kube_hpa_desired_replicas.libsonnet',
  import 'kube_persistent_volume_claim_disk_space.libsonnet',
  import 'kube_persistent_volume_claim_inodes.libsonnet',
  import 'kube_pool_max_nodes.libsonnet',
  import 'memory.libsonnet',
  import 'nat_gateway_port_allocation.libsonnet',
  import 'nat_host_port_allocation.libsonnet',
  import 'nf_conntrack_entries.libsonnet',
  import 'node_schedstat_waiting.libsonnet',
  import 'open_fds.libsonnet',
  import 'pg_active_db_connections_primary.libsonnet',
  import 'pg_active_db_connections_replica.libsonnet',
  import 'pg_int4_id.libsonnet',
  import 'pg_txid_wraparound.libsonnet',
  import 'pg_vacuum_activity.libsonnet',
  import 'pg_walsender_cpu.libsonnet',
  import 'pgbouncer_client_connections.libsonnet',
  import 'pgbouncer_pools.libsonnet',
  import 'pgbouncer_single_core.libsonnet',
  import 'praefect_cloudsql_cpu.libsonnet',
  import 'private_runners.libsonnet',
  import 'pvs_cloudrun_container_instances.libsonnet',
  import 'rails_db_connection_pool.libsonnet',
  import 'redis_clients.libsonnet',
  import 'redis_memory.libsonnet',
  import 'redis_primary_cpu.libsonnet',
  import 'redis_secondary_cpu.libsonnet',
  import 'ruby_thread_contention.libsonnet',
  import 'shard_cpu.libsonnet',
  import 'shared_runners_gitlab.libsonnet',
  import 'shared_runners.libsonnet',
  import 'sidekiq_shard_workers.libsonnet',
  import 'single_node_cpu.libsonnet',
  import 'single_node_puma_workers.libsonnet',
  import 'workhorse_image_scaling.libsonnet',
];

std.foldl(
  function(memo, module)
    memo + module,
  saturationTypes,
  {}
)
