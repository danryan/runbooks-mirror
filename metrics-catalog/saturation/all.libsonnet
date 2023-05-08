[
  import 'saturation-monitoring/cgroup_memory.libsonnet',
  import 'saturation-monitoring/cloudsql_cpu.libsonnet',
  import 'saturation-monitoring/cloudsql_disk.libsonnet',
  import 'saturation-monitoring/cloudsql_memory.libsonnet',
  import 'saturation-monitoring/cpu.libsonnet',
  import 'saturation-monitoring/disk_inodes.libsonnet',
  import 'saturation-monitoring/disk_space.libsonnet',
  import 'saturation-monitoring/disk_sustained_read_iops.libsonnet',
  import 'saturation-monitoring/disk_sustained_read_throughput.libsonnet',
  import 'saturation-monitoring/disk_sustained_write_iops.libsonnet',
  import 'saturation-monitoring/disk_sustained_write_throughput.libsonnet',
  import 'saturation-monitoring/elastic_cpu.libsonnet',
  import 'saturation-monitoring/elastic_disk_space.libsonnet',
  import 'saturation-monitoring/elastic_jvm_heap_memory.libsonnet',
  import 'saturation-monitoring/elastic_single_node_cpu.libsonnet',
  import 'saturation-monitoring/elastic_single_node_disk_space.libsonnet',
  import 'saturation-monitoring/elastic_thread_pools.libsonnet',
  import 'saturation-monitoring/gcp_quota_limit.libsonnet',
  import 'saturation-monitoring/gitaly_total_disk_space.libsonnet',
  import 'saturation-monitoring/gitaly_active_node_available_space.libsonnet',
  import 'saturation-monitoring/go_memory.libsonnet',
  import 'saturation-monitoring/kube_container_cpu.libsonnet',
  import 'saturation-monitoring/kube_container_memory.libsonnet',
  import 'saturation-monitoring/kube_container_rss.libsonnet',
  import 'saturation-monitoring/kube_go_memory.libsonnet',
  import 'saturation-monitoring/kube_horizontalpodautoscaler_desired_replicas.libsonnet',
  import 'saturation-monitoring/kube_node_ips.libsonnet',
  import 'saturation-monitoring/kube_persistent_volume_claim_disk_space.libsonnet',
  import 'saturation-monitoring/kube_persistent_volume_claim_inodes.libsonnet',
  import 'saturation-monitoring/kube_pool_cpu.libsonnet',
  import 'saturation-monitoring/kube_pool_max_nodes.libsonnet',
  import 'saturation-monitoring/memory.libsonnet',
  import 'saturation-monitoring/nat_gateway_port_allocation.libsonnet',
  import 'saturation-monitoring/nat_host_port_allocation.libsonnet',
  import 'saturation-monitoring/nf_conntrack_entries.libsonnet',
  import 'saturation-monitoring/node_schedstat_waiting.libsonnet',
  import 'saturation-monitoring/open_fds.libsonnet',
  import 'saturation-monitoring/pg_active_db_connections_primary.libsonnet',
  import 'saturation-monitoring/pg_active_db_connections_replica.libsonnet',
  import 'saturation-monitoring/pg_btree_bloat.libsonnet',
  import 'saturation-monitoring/pg_int4_id.libsonnet',
  import 'saturation-monitoring/pg_primary_cpu.libsonnet',
  import 'saturation-monitoring/pg_table_bloat.libsonnet',
  import 'saturation-monitoring/pg_txid_vacuum_to_wraparound.libsonnet',
  import 'saturation-monitoring/pg_txid_wraparound.libsonnet',
  import 'saturation-monitoring/pg_vacuum_activity.libsonnet',
  import 'saturation-monitoring/pg_walsender_cpu.libsonnet',
  import 'saturation-monitoring/pgbouncer_client_connections.libsonnet',
  import 'saturation-monitoring/pgbouncer_pools.libsonnet',
  import 'saturation-monitoring/pgbouncer_single_core.libsonnet',
  import 'saturation-monitoring/private_runners.libsonnet',
  import 'saturation-monitoring/pvs_cloudrun_container_instances.libsonnet',
  import 'saturation-monitoring/rails_db_connection_pool.libsonnet',
  import 'saturation-monitoring/redis_clients.libsonnet',
  import 'saturation-monitoring/redis_memory.libsonnet',
  import 'saturation-monitoring/redis_primary_cpu.libsonnet',
  import 'saturation-monitoring/redis_secondary_cpu.libsonnet',
  import 'saturation-monitoring/ruby_thread_contention.libsonnet',
  import 'saturation-monitoring/shard_cpu.libsonnet',
  import 'saturation-monitoring/shared_runners.libsonnet',
  import 'saturation-monitoring/shared_runners_gitlab.libsonnet',
  import 'saturation-monitoring/sidekiq_shard_workers.libsonnet',
  import 'saturation-monitoring/single_node_cpu.libsonnet',
  import 'saturation-monitoring/single_node_puma_workers.libsonnet',
  import 'saturation-monitoring/workhorse_image_scaling.libsonnet',
]