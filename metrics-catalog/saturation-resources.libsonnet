local sidekiqHelpers = import './services/lib/sidekiq-helpers.libsonnet';
local metricsCatalog = import 'servicemetrics/metrics.libsonnet';

local resourceSaturationPoint = metricsCatalog.resourceSaturationPoint;

local kubeProvisionedServices = ['git', 'mailroom', 'registry', 'sidekiq'];

// Disk utilisation metrics are currently reporting incorrectly for
// HDD volumes, see https://gitlab.com/gitlab-com/gl-infra/infrastructure/-/issues/10248
// as such, we only record this utilisation metric on IO subset of the fleet for now.
local diskPerformanceSensitiveServices = ['patroni', 'gitaly', 'nfs'];

local pgbouncerAsyncPool(serviceType, role) =
  resourceSaturationPoint({
    title: 'Postgres Async (Sidekiq) %s Connection Pool Utilization per Node' % [role],
    severity: 's4',
    horizontallyScalable: role == 'replica',  // Replicas can be scaled horizontally, primary cannot
    appliesTo: [serviceType],
    description: |||
      pgbouncer async connection pool utilization per database node, for %(role)s database connections.

      Sidekiq maintains it's own pgbouncer connection pool. When this resource is saturated,
      database operations may queue, leading to additional latency in background processing.
    ||| % { role: role },
    grafana_dashboard_uid: 'sat_pgbouncer_async_pool_' + role,
    resourceLabels: ['fqdn', 'instance'],
    burnRatePeriod: '5m',
    query: |||
      (
        avg_over_time(pgbouncer_pools_server_active_connections{user="gitlab", database="gitlabhq_production_sidekiq", %(selector)s}[%(rangeInterval)s]) +
        avg_over_time(pgbouncer_pools_server_testing_connections{user="gitlab", database="gitlabhq_production_sidekiq", %(selector)s}[%(rangeInterval)s]) +
        avg_over_time(pgbouncer_pools_server_used_connections{user="gitlab", database="gitlabhq_production_sidekiq", %(selector)s}[%(rangeInterval)s]) +
        avg_over_time(pgbouncer_pools_server_login_connections{user="gitlab", database="gitlabhq_production_sidekiq", %(selector)s}[%(rangeInterval)s])
      )
      / on(%(aggregationLabels)s) group_left()
      sum by (%(aggregationLabels)s) (
        avg_over_time(pgbouncer_databases_pool_size{name="gitlabhq_production_sidekiq", %(selector)s}[%(rangeInterval)s])
      )
    |||,
    slos: {
      soft: 0.90,
      hard: 0.95,
      alertTriggerDuration: '10m',
    },
  });

local pgbouncerSyncPool(serviceType, role) =
  resourceSaturationPoint({
    title: 'Postgres Sync (Web/API/Git) %s Connection Pool Utilization per Node' % [role],
    severity: 's3',
    horizontallyScalable: role == 'replica',  // Replicas can be scaled horizontally, primary cannot
    appliesTo: [serviceType],
    description: |||
      pgbouncer sync connection pool Saturation per database node, for %(role)s database connections.

      Web/api/git applications use a separate connection pool to sidekiq.

      When this resource is saturated, web/api database operations may queue, leading to rails worker
      saturation and 503 errors in the web.
    ||| % { role: role },
    grafana_dashboard_uid: 'sat_pgbouncer_sync_pool_' + role,
    resourceLabels: ['fqdn', 'instance'],
    burnRatePeriod: '5m',
    query: |||
      (
        avg_over_time(pgbouncer_pools_server_active_connections{user="gitlab", database="gitlabhq_production", %(selector)s}[%(rangeInterval)s]) +
        avg_over_time(pgbouncer_pools_server_testing_connections{user="gitlab", database="gitlabhq_production", %(selector)s}[%(rangeInterval)s]) +
        avg_over_time(pgbouncer_pools_server_used_connections{user="gitlab", database="gitlabhq_production", %(selector)s}[%(rangeInterval)s]) +
        avg_over_time(pgbouncer_pools_server_login_connections{user="gitlab", database="gitlabhq_production", %(selector)s}[%(rangeInterval)s])
      )
      / on(%(aggregationLabels)s) group_left()
      sum by (%(aggregationLabels)s) (
        avg_over_time(pgbouncer_databases_pool_size{name="gitlabhq_production", %(selector)s}[%(rangeInterval)s])
      )
    |||,
    slos: {
      soft: 0.85,
      hard: 0.95,
      alertTriggerDuration: '10m',
    },
  });

{
  pg_active_db_connections_primary: resourceSaturationPoint({
    title: 'Active Primary DB Connection Utilization',
    severity: 's3',
    horizontallyScalable: false,  // Connections to the primary are not horizontally scalable
    appliesTo: ['patroni'],
    description: |||
      Active db connection utilization on the primary node.

      Postgres is configured to use a maximum number of connections.
      When this resource is saturated, connections may queue.
    |||,
    grafana_dashboard_uid: 'sat_active_db_connections_primary',
    resourceLabels: ['fqdn'],
    query: |||
      sum without (state) (
        pg_stat_activity_count{datname="gitlabhq_production", state!="idle", %(selector)s} unless on(instance) (pg_replication_is_replica == 1)
      )
      / on (%(aggregationLabels)s)
      pg_settings_max_connections{%(selector)s}
    |||,
    slos: {
      soft: 0.70,
      hard: 0.80,
    },
  }),

  pg_active_db_connections_replica: resourceSaturationPoint({
    title: 'Active Secondary DB Connection Utilization',
    severity: 's3',
    horizontallyScalable: true,  // Connections to the replicas are horizontally scalable
    appliesTo: ['patroni'],
    description: |||
      Active db connection utilization per replica node

      Postgres is configured to use a maximum number of connections.
      When this resource is saturated, connections may queue.
    |||,
    grafana_dashboard_uid: 'sat_active_db_connections_replica',
    resourceLabels: ['fqdn'],
    query: |||
      sum without (state) (
        pg_stat_activity_count{datname="gitlabhq_production", state!="idle", %(selector)s} and on(instance) (pg_replication_is_replica == 1)
      )
      / on (%(aggregationLabels)s)
      pg_settings_max_connections{%(selector)s}
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),

  rails_db_connection_pool: resourceSaturationPoint({
    title: 'Rails DB Connection Pool Utilization',
    severity: 's4',
    horizontallyScalable: true,  // Add more replicas for achieve greater scalability
    appliesTo: ['web', 'api', 'git', 'sidekiq'],
    description: |||
      Rails uses connection pools for its database connections. As each
      node may have multiple connection pools, this is by node and by
      database host.

      Read more about this resource in our [documentation](https://docs.gitlab.com/ee/development/database/client_side_connection_pool.html#client-side-connection-pool).

      If this resource is saturated, it may indicate that our connection
      pools are not correctly sized, perhaps because an unexpected
      application thread is using a database connection.
    |||,
    grafana_dashboard_uid: 'sat_rails_db_connection_pool',
    resourceLabels: ['instance', 'host', 'port'],
    burnRatePeriod: '5m',
    query: |||
      (
        avg_over_time(gitlab_database_connection_pool_busy{class="ActiveRecord::Base", %(selector)s}[%(rangeInterval)s])
        +
        avg_over_time(gitlab_database_connection_pool_dead{class="ActiveRecord::Base", %(selector)s}[%(rangeInterval)s])
      )
      /
      gitlab_database_connection_pool_size{class="ActiveRecord::Base", %(selector)s}
    |||,
    slos: {
      soft: 0.90,
      hard: 0.99,
      alertTriggerDuration: '15m',
    },
  }),

  cgroup_memory: resourceSaturationPoint({
    title: 'Cgroup Memory Utilization per Node',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: ['gitaly', 'praefect'],
    description: |||
      Cgroup memory utilization per node.

      Some services, notably Gitaly, are configured to run within a cgroup with a memory limit lower than the
      memory limit for the node. This ensures that a traffic spike to Gitaly does not affect other services on the node.

      If this resource is becoming saturated, this may indicate traffic spikes to Gitaly, abuse or possibly resource leaks in
      the application. Gitaly or other git processes may be killed by the OOM killer when this resource is saturated.
    |||,
    grafana_dashboard_uid: 'sat_cgroup_memory',
    resourceLabels: ['fqdn'],
    query: |||
      (
        container_memory_usage_bytes{id="/system.slice/gitlab-runsvdir.service", %(selector)s} -
        container_memory_cache{id="/system.slice/gitlab-runsvdir.service", %(selector)s} -
        container_memory_swap{id="/system.slice/gitlab-runsvdir.service", %(selector)s}
      )
      /
      container_spec_memory_limit_bytes{id="/system.slice/gitlab-runsvdir.service", %(selector)s}
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),

  cpu: resourceSaturationPoint({
    title: 'Average Service CPU Utilization',
    severity: 's3',
    horizontallyScalable: true,
    appliesTo: { allExcept: ['waf', 'console-node', 'deploy-node', 'security' /* ops-only security scanning service */] },
    description: |||
      This resource measures average CPU utilization across an all cores in a service fleet.
      If it is becoming saturated, it may indicate that the fleet needs
      horizontal or vertical scaling.
    |||,
    grafana_dashboard_uid: 'sat_cpu',
    resourceLabels: [],
    burnRatePeriod: '5m',
    query: |||
      1 - avg by (%(aggregationLabels)s) (
        rate(node_cpu_seconds_total{mode="idle", %(selector)s}[%(rangeInterval)s])
      )
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),

  shard_cpu: resourceSaturationPoint({
    title: 'Average CPU Utilization per Shard',
    severity: 's3',
    horizontallyScalable: true,
    appliesTo: { allExcept: ['waf', 'console-node', 'deploy-node', 'security' /* ops-only security scanning service */], default: 'sidekiq' },
    description: |||
      This resource measures average CPU utilization across an all cores in a shard of a
      service fleet. If it is becoming saturated, it may indicate that the
      shard needs horizontal or vertical scaling.
    |||,
    grafana_dashboard_uid: 'sat_shard_cpu',
    resourceLabels: ['shard'],
    burnRatePeriod: '5m',
    query: |||
      1 - avg by (%(aggregationLabels)s) (
        rate(node_cpu_seconds_total{mode="idle", %(selector)s}[%(rangeInterval)s])
      )
    |||,
    slos: {
      soft: 0.85,
      hard: 0.95,
    },
  }),

  disk_space: resourceSaturationPoint({
    title: 'Disk Space Utilization per Device per Node',
    severity: 's2',
    horizontallyScalable: true,
    appliesTo: { allExcept: ['waf', 'bastion'], default: 'gitaly' },
    description: |||
      Disk space utilization per device per node.
    |||,
    grafana_dashboard_uid: 'sat_disk_space',
    resourceLabels: ['fqdn', 'device'],
    query: |||
      (
        1 - instance:node_filesystem_avail:ratio{fstype=~"ext.|xfs", %(selector)s}
      )
    |||,
    slos: {
      soft: 0.85,
      hard: 0.90,
    },
  }),

  disk_inodes: resourceSaturationPoint({
    title: 'Disk inode Utilization per Device per Node',
    severity: 's2',
    horizontallyScalable: true,
    appliesTo: { allExcept: ['waf', 'bastion'], default: 'gitaly' },
    description: |||
      Disk inode utilization per device per node.

      If this is too high, its possible that a directory is filling up with
      files. Consider logging in an checking temp directories for large numbers
      of files
    |||,
    grafana_dashboard_uid: 'sat_disk_inodes',
    resourceLabels: ['fqdn', 'device'],
    query: |||
      1 - (
        node_filesystem_files_free{fstype=~"(ext.|xfs)", %(selector)s}
        /
        node_filesystem_files{fstype=~"(ext.|xfs)", %(selector)s}
      )
    |||,
    slos: {
      soft: 0.75,
      hard: 0.80,
      alertTriggerDuration: '15m',
    },
  }),

  disk_sustained_read_iops: resourceSaturationPoint({
    title: 'Disk Sustained Read IOPS Utilization per Node',
    severity: 's3',
    horizontallyScalable: true,
    appliesTo: diskPerformanceSensitiveServices,
    description: |||
      Disk sustained read IOPS utilization per node.
    |||,
    grafana_dashboard_uid: 'sat_disk_sus_read_iops',
    resourceLabels: ['fqdn', 'device'],
    query: |||
      rate(node_disk_reads_completed_total{device!="sda", %(selector)s}[%(rangeInterval)s])
      /
      node_disk_max_read_iops{device!="sda", %(selector)s}
    |||,
    burnRatePeriod: '20m',
    slos: {
      soft: 0.80,
      hard: 0.90,
      alertTriggerDuration: '25m',
    },
  }),

  disk_sustained_read_throughput: resourceSaturationPoint({
    title: 'Disk Sustained Read Throughput Utilization per Node',
    severity: 's3',
    horizontallyScalable: true,
    appliesTo: diskPerformanceSensitiveServices,
    description: |||
      Disk sustained read throughput utilization per node.
    |||,
    grafana_dashboard_uid: 'sat_disk_sus_read_throughput',
    resourceLabels: ['fqdn', 'device'],
    query: |||
      rate(node_disk_read_bytes_total{device!="sda", %(selector)s}[%(rangeInterval)s])
      /
      node_disk_max_read_bytes_seconds{device!="sda", %(selector)s}
    |||,
    burnRatePeriod: '20m',
    slos: {
      soft: 0.70,
      hard: 0.80,
      alertTriggerDuration: '25m',
    },
  }),

  disk_sustained_write_iops: resourceSaturationPoint({
    title: 'Disk Sustained Write IOPS Utilization per Node',
    severity: 's3',
    horizontallyScalable: true,
    appliesTo: diskPerformanceSensitiveServices,
    description: |||
      Gitaly runs on Google Cloud's Persistent Disk product. This has a published sustained
      maximum write IOPS value. This value can be exceeded for brief periods.

      If a single node is consistently reaching saturation, it may indicate a noisy-neighbour repository,
      possible abuse or it may indicate that the node needs rebalancing.

      More information can be found at
      https://cloud.google.com/compute/docs/disks/performance.
    |||,
    grafana_dashboard_uid: 'sat_disk_sus_write_iops',
    resourceLabels: ['fqdn', 'device'],
    query: |||
      rate(node_disk_writes_completed_total{device!="sda", %(selector)s}[%(rangeInterval)s])
      /
      node_disk_max_write_iops{device!="sda", %(selector)s}
    |||,
    burnRatePeriod: '20m',
    slos: {
      soft: 0.80,
      hard: 0.90,
      alertTriggerDuration: '25m',
    },
  }),

  disk_sustained_write_throughput: resourceSaturationPoint({
    title: 'Disk Sustained Write Throughput Utilization per Node',
    severity: 's3',
    horizontallyScalable: true,
    appliesTo: diskPerformanceSensitiveServices,
    description: |||
      Gitaly runs on Google Cloud's Persistent Disk product. This has a published sustained
      maximum write throughput value. This value can be exceeded for brief periods.

      If a single node is consistently reaching saturation, it may indicate a noisy-neighbour repository,
      possible abuse or it may indicate that the node needs rebalancing.

      More information can be found at
      https://cloud.google.com/compute/docs/disks/performance.
    |||,
    grafana_dashboard_uid: 'sat_disk_sus_write_throughput',
    resourceLabels: ['fqdn', 'device'],
    query: |||
      rate(node_disk_written_bytes_total{device!="sda", %(selector)s}[%(rangeInterval)s])
      /
      node_disk_max_write_bytes_seconds{device!="sda", %(selector)s}
    |||,
    burnRatePeriod: '20m',
    slos: {
      soft: 0.70,
      hard: 0.80,
      alertTriggerDuration: '25m',
    },
  }),

  elastic_cpu: resourceSaturationPoint({
    title: 'Average CPU Utilization per Node',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: ['logging', 'search'],
    description: |||
      Average CPU utilization per Node.

      This resource measures all CPU across a fleet. If it is becoming saturated, it may indicate that the fleet needs horizontal or
      vertical scaling. The metrics are coming from elasticsearch_exporter.
    |||,
    grafana_dashboard_uid: 'sat_elastic_cpu',
    resourceLabels: [],
    query: |||
      avg by (%(aggregationLabels)s) (
        avg_over_time(elasticsearch_process_cpu_percent{%(selector)s}[%(rangeInterval)s]) / 100
      )
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),

  elastic_disk_space: resourceSaturationPoint({
    title: 'Disk Utilization Overall',
    severity: 's3',
    horizontallyScalable: true,
    appliesTo: ['logging', 'search'],
    description: |||
      Disk utilization per device per node.
    |||,
    grafana_dashboard_uid: 'sat_elastic_disk_space',
    resourceLabels: [],
    query: |||
      sum by (%(aggregationLabels)s) (
        (elasticsearch_filesystem_data_size_bytes{%(selector)s} - elasticsearch_filesystem_data_free_bytes{%(selector)s})
      )
      /
      sum by (%(aggregationLabels)s) (
        elasticsearch_filesystem_data_size_bytes{%(selector)s}
      )
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),

  elastic_jvm_heap_memory: resourceSaturationPoint({
    title: 'JVM Heap Utilization per Node',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: ['logging', 'search'],
    description: |||
      JVM heap memory utilization per node.
    |||,
    grafana_dashboard_uid: 'sat_elastic_jvm_heap_memory',
    resourceLabels: ['name'],
    query: |||
      elasticsearch_jvm_memory_used_bytes{area="heap", %(selector)s}
      /
      elasticsearch_jvm_memory_max_bytes{area="heap", %(selector)s}
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),

  elastic_single_node_cpu: resourceSaturationPoint({
    title: 'Average CPU Utilization per Node',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: ['logging', 'search'],
    description: |||
      Average CPU per Node.

      This resource measures all CPU across a fleet. If it is becoming saturated, it may indicate that the fleet needs horizontal or
      vertical scaling. The metrics are coming from elasticsearch_exporter.
    |||,
    grafana_dashboard_uid: 'sat_elastic_single_node_cpu',
    resourceLabels: ['name'],
    burnRatePeriod: '5m',
    query: |||
      avg_over_time(elasticsearch_process_cpu_percent{%(selector)s}[%(rangeInterval)s]) / 100
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),

  elastic_single_node_disk_space: resourceSaturationPoint({
    title: 'Disk Utilization per Device per Node',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: ['logging', 'search'],
    description: |||
      Disk utilization per device per node.
    |||,
    grafana_dashboard_uid: 'sat_elastic_node_disk_space',
    resourceLabels: ['name'],
    query: |||
      (
        (
          elasticsearch_filesystem_data_size_bytes{%(selector)s}
          -
          elasticsearch_filesystem_data_free_bytes{%(selector)s}
        )
        /
        elasticsearch_filesystem_data_size_bytes{%(selector)s}
      )
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),

  elastic_thread_pools: resourceSaturationPoint({
    title: 'Thread pool utilization',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: ['logging', 'search'],
    description: |||
      Utilization of each thread pool on each node.

      Descriptions of the threadpool types can be found at
      https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-threadpool.html.
    |||,
    grafana_dashboard_uid: 'sat_elastic_thread_pools',
    resourceLabels: ['name', 'exported_type'],
    burnRatePeriod: '5m',
    query: |||
      (
        avg_over_time(elasticsearch_thread_pool_active_count{exported_type!="snapshot", %(selector)s}[%(rangeInterval)s])
        /
        (avg_over_time(elasticsearch_thread_pool_threads_count{exported_type!="snapshot", %(selector)s}[%(rangeInterval)s]) > 0)
      )
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),

  go_memory: resourceSaturationPoint({
    title: 'Go Memory Utilization per Node',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: ['gitaly', 'web-pages', 'monitoring', 'web', 'praefect', 'registry', 'api'],
    description: |||
      Go's memory allocation strategy can make it look like a Go process is saturating memory when measured using RSS, when in fact
      the process is not at risk of memory saturation. For this reason, we measure Go processes using the `go_memstat_alloc_bytes`
      metric instead of RSS.
    |||,
    grafana_dashboard_uid: 'sat_go_memory',
    resourceLabels: ['fqdn'],
    query: |||
      sum by (%(aggregationLabels)s) (
        go_memstats_alloc_bytes{%(selector)s}
      )
      /
      sum by (%(aggregationLabels)s) (
        node_memory_MemTotal_bytes{%(selector)s}
      )
    |||,
    slos: {
      soft: 0.90,
      hard: 0.98,
    },
  }),

  memory: resourceSaturationPoint({
    title: 'Memory Utilization per Node',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: { allExcept: ['waf', 'monitoring'] },
    description: |||
      Memory utilization per device per node.
    |||,
    grafana_dashboard_uid: 'sat_memory',
    resourceLabels: ['fqdn'],
    query: |||
      instance:node_memory_utilization:ratio{%(selector)s}
    |||,
    slos: {
      soft: 0.90,
      hard: 0.98,
    },
  }),

  open_fds: resourceSaturationPoint({
    title: 'Open file descriptor utilization per instance',
    severity: 's2',
    horizontallyScalable: true,
    appliesTo: { allExcept: ['waf'] },
    description: |||
      Open file descriptor utilization per instance.

      Saturation on file descriptor limits may indicate a resource-descriptor leak in the application.

      As a temporary fix, you may want to consider restarting the affected process.
    |||,
    grafana_dashboard_uid: 'sat_open_fds',
    resourceLabels: ['job', 'instance'],
    query: |||
      (
        process_open_fds{%(selector)s}
        /
        process_max_fds{%(selector)s}
      )
      or
      (
        ruby_file_descriptors{%(selector)s}
        /
        ruby_process_max_fds{%(selector)s}
      )
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),

  ruby_thread_contention: resourceSaturationPoint({
    title: 'Ruby Thread Contention',
    severity: 's3',
    horizontallyScalable: true,  // Add more replicas for achieve greater scalability
    appliesTo: ['web', 'sidekiq', 'api', 'git', 'websockets'],
    description: |||
      Ruby (technically Ruby MRI), like some other scripting languages, uses a Global VM lock (GVL) also known as a
      Global Interpreter Lock (GIL) to ensure that multiple threads can execute safely. Ruby code is only allowed to
      execute in one thread in a process at a time. When calling out to c extensions, the thread can cede the lock to
      other thread while it continues to execute.

      This means that when CPU-bound workloads run in a multithreaded environment such as Puma or Sidekiq, contention
      with other Ruby worker threads running in the same process can occur, effectively slowing thoses threads down as
      they await GVL entry.

      Often the best fix for this situation is to add more workers by scaling up the fleet.
    |||,
    grafana_dashboard_uid: 'sat_ruby_thread_contention',
    resourceLabels: ['fqdn', 'pod'],  // We need both because `instance` is still an unreadable IP :|
    burnRatePeriod: '10m',
    query: |||
      rate(ruby_process_cpu_seconds_total{%(selector)s}[%(rangeInterval)s])
    |||,
    slos: {
      soft: 0.70,
      hard: 0.75,
    },
  }),

  workhorse_image_scaling: resourceSaturationPoint({
    title: 'Workhorse Image Scaler Exhaustion per Node',
    severity: 's4',
    horizontallyScalable: true,  // Add more replicas for achieve greater scalability
    appliesTo: ['web'],
    description: |||
      Workhorse can scale images on-the-fly as requested. Since the actual work will be
      performed by dedicated processes, we currently define a hard cap for how many
      such requests are allowed to be in the system concurrently.

      If this resource is fully saturated, Workhorse will start ignoring image scaling
      requests and serve the original image instead, which will ensure continued operation,
      but comes at the cost of additional client latency and GCS egress traffic.
    |||,
    grafana_dashboard_uid: 'sat_wh_image_scaling',
    resourceLabels: ['fqdn'],
    burnRatePeriod: '5m',
    query: |||
      avg_over_time(gitlab_workhorse_image_resize_processes{%(selector)s}[%(rangeInterval)s])
        /
      gitlab_workhorse_image_resize_max_processes{%(selector)s}
    |||,
    slos: {
      soft: 0.90,
      hard: 0.95,
      alertTriggerDuration: '15m',
    },
  }),

  pgbouncer_async_primary_pool: pgbouncerAsyncPool('pgbouncer', 'primary'),

  // Note that this pool is currently not used, but may be added in the medium
  // term
  // pgbouncer_async_replica_pool: pgbouncerAsyncPool('patroni', 'replica'),
  pgbouncer_sync_primary_pool: pgbouncerSyncPool('pgbouncer', 'primary'),
  pgbouncer_sync_replica_pool: pgbouncerSyncPool('patroni', 'replica'),

  pgbouncer_single_core: resourceSaturationPoint({
    title: 'PGBouncer Single Core per Node',
    severity: 's2',
    horizontallyScalable: true,  // Add more pgbouncer processes (for patroni) or nodes (for pgbouncer)
    appliesTo: ['pgbouncer', 'patroni'],
    description: |||
      PGBouncer single core CPU utilization per node.

      PGBouncer is a single threaded application. Under high volumes this resource may become saturated,
      and additional pgbouncer nodes may need to be provisioned.
    |||,
    grafana_dashboard_uid: 'sat_pgbouncer_single_core',
    resourceLabels: ['fqdn', 'groupname'],
    burnRatePeriod: '5m',
    query: |||
      sum without(cpu, mode) (
        rate(
          namedprocess_namegroup_cpu_seconds_total{groupname=~"pgbouncer.*", %(selector)s}[%(rangeInterval)s]
        )
      )
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),

  private_runners: resourceSaturationPoint({
    title: 'Private Runners utilization',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: ['ci-runners'],
    description: |||
      Private runners utilization per instance.

      Each runner manager has a maximum number of runners that it can coordinate at any single moment.

      When this metric is saturated, new CI jobs will queue. When this occurs we should consider adding more runner managers,
      or scaling the runner managers vertically and increasing their maximum runner capacity.
    |||,
    grafana_dashboard_uid: 'sat_private_runners',
    resourceLabels: ['instance'],
    staticLabels: {
      type: 'ci-runners',
      tier: 'runners',
      stage: 'main',
    },
    query: |||
      sum without(executor_stage, exported_stage, state) (
        max_over_time(gitlab_runner_jobs{job="runners-manager",shard="private"}[%(rangeInterval)s])
      )
      /
      gitlab_runner_limit{job="runners-manager",shard="private"} > 0
    |||,
    slos: {
      soft: 0.85,
      hard: 0.95,
    },
  }),

  redis_clients: resourceSaturationPoint({
    title: 'Redis Client Utilization per Node',
    severity: 's3',
    horizontallyScalable: false,
    appliesTo: ['redis', 'redis-sidekiq', 'redis-cache'],
    description: |||
      Redis client utilization per node.

      A redis server has a maximum number of clients that can connect. When this resource is saturated,
      new clients may fail to connect.

      More details at https://redis.io/topics/clients#maximum-number-of-clients
    |||,
    grafana_dashboard_uid: 'sat_redis_clients',
    resourceLabels: ['fqdn'],
    query: |||
      max_over_time(redis_connected_clients{%(selector)s}[%(rangeInterval)s])
      /
      redis_config_maxclients{%(selector)s}
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),

  redis_memory: resourceSaturationPoint({
    title: 'Redis Memory Utilization per Node',
    severity: 's2',
    horizontallyScalable: false,
    appliesTo: ['redis', 'redis-sidekiq', 'redis-cache'],
    description: |||
      Redis memory utilization per node.

      As Redis memory saturates node memory, the likelyhood of OOM kills, possibly to the Redis process,
      become more likely.

      For caches, consider lowering the `maxmemory` setting in Redis. For non-caching Redis instances,
      this has been caused in the past by credential stuffing, leading to large numbers of web sessions.
    |||,
    grafana_dashboard_uid: 'sat_redis_memory',
    resourceLabels: ['fqdn'],
    query: |||
      max by (%(aggregationLabels)s) (
        label_replace(redis_memory_used_rss_bytes{%(selector)s}, "memtype", "rss","","")
        or
        label_replace(redis_memory_used_bytes{%(selector)s}, "memtype", "used","","")
      )
      /
      avg by (%(aggregationLabels)s) (
        node_memory_MemTotal_bytes{%(selector)s}
      )
    |||,
    slos: {
      soft: 0.65,
      hard: 0.75,
    },
  }),

  shared_runners: resourceSaturationPoint({
    title: 'Shared Runner utilization',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: ['ci-runners'],
    description: |||
      Shared runner utilization per instance.

      Each runner manager has a maximum number of runners that it can coordinate at any single moment.

      When this metric is saturated, new CI jobs will queue. When this occurs we should consider adding more runner managers,
      or scaling the runner managers vertically and increasing their maximum runner capacity.
    |||,
    grafana_dashboard_uid: 'sat_shared_runners',
    resourceLabels: ['instance'],
    staticLabels: {
      type: 'ci-runners',
      tier: 'runners',
      stage: 'main',
    },
    query: |||
      sum without(executor_stage, exported_stage, state) (
        max_over_time(gitlab_runner_jobs{job="runners-manager",shard="shared"}[%(rangeInterval)s])
      )
      /
      gitlab_runner_limit{job="runners-manager",shard="shared"} > 0
    |||,
    slos: {
      soft: 0.90,
      hard: 0.95,
    },
  }),

  shared_runners_gitlab: resourceSaturationPoint({
    title: 'Shared Runner GitLab Utilization',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: ['ci-runners'],
    description: |||
      Shared runners utilization per instance.

      Each runner manager has a maximum number of runners that it can coordinate at any single moment.

      When this metric is saturated, new CI jobs will queue. When this occurs we should consider adding more runner managers,
      or scaling the runner managers vertically and increasing their maximum runner capacity.
    |||,
    grafana_dashboard_uid: 'sat_shared_runners_gitlab',
    resourceLabels: ['instance'],
    // TODO: remove relabelling silliness once
    // https://gitlab.com/gitlab-com/gl-infra/infrastructure/-/issues/8456
    // is completed
    query: |||
      sum without(executor_stage, exported_stage, state) (
        max_over_time(gitlab_runner_jobs{job="runners-manager",shard="shared-gitlab-org"}[%(rangeInterval)s])
      )
      /
      gitlab_runner_limit{job="runners-manager",shard="shared-gitlab-org"} > 0
    |||,
    slos: {
      soft: 0.90,
      hard: 0.95,
    },
  }),

  sidekiq_shard_workers: resourceSaturationPoint({
    title: 'Sidekiq Worker Utilization per shard',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: ['sidekiq'],
    description: |||
      Sidekiq worker utilization per shard.

      This metric represents the percentage of available threads*workers that are actively processing jobs.

      When this metric is saturated, new Sidekiq jobs will queue. Depending on whether or not the jobs are latency sensitive,
      this could impact user experience.
    |||,
    grafana_dashboard_uid: 'sat_sidekiq_shard_workers',
    resourceLabels: ['shard'],
    burnRatePeriod: '5m',
    query: |||
      sum by (%(aggregationLabels)s) (
        avg_over_time(sidekiq_running_jobs{shard!~"%(throttledSidekiqShardsRegexp)s", %(selector)s}[%(rangeInterval)s])
      )
      /
      sum by (%(aggregationLabels)s) (
        avg_over_time(sidekiq_concurrency{shard!~"%(throttledSidekiqShardsRegexp)s", %(selector)s}[%(rangeInterval)s])
      )
    |||,
    queryFormatConfig: {
      throttledSidekiqShardsRegexp: std.join('|', sidekiqHelpers.shards.listFiltered(function(shard) shard.urgency == 'throttled')),
    },
    slos: {
      soft: 0.85,
      hard: 0.90,
      alertTriggerDuration: '10m',
    },
  }),

  single_node_cpu: resourceSaturationPoint({
    title: 'Average CPU Utilization per Node',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: { allExcept: ['waf', 'console-node', 'deploy-node', 'security' /* ops-only security scanning service */] },
    description: |||
      Average CPU utilization per Node.

      If average CPU is satured, it may indicate that a fleet is in need to horizontal or vertical scaling. It may also indicate
      imbalances in load in a fleet.
    |||,
    grafana_dashboard_uid: 'sat_single_node_cpu',
    resourceLabels: ['fqdn'],
    burnRatePeriod: '5m',
    query: |||
      avg without(cpu, mode) (1 - rate(node_cpu_seconds_total{mode="idle", %(selector)s}[%(rangeInterval)s]))
    |||,
    slos: {
      soft: 0.90,
      hard: 0.95,
      alertTriggerDuration: '10m',
    },
  }),

  single_node_puma_workers: resourceSaturationPoint({
    title: 'Puma Worker Saturation per Node',
    severity: 's2',
    horizontallyScalable: true,
    appliesTo: ['web', 'api', 'git', 'sidekiq'],
    description: |||
      Puma thread utilization per node.

      Puma uses a fixed size thread pool to handle HTTP requests. This metric shows how many threads are busy handling requests. When this resource is saturated,
      we will see puma queuing taking place. Leading to slowdowns across the application.

      Puma saturation is usually caused by latency problems in downstream services: usually Gitaly or Postgres, but possibly also Redis.
      Puma saturation can also be caused by traffic spikes.
    |||,
    grafana_dashboard_uid: 'sat_single_node_puma_workers',
    resourceLabels: ['fqdn'],
    query: |||
      sum by(%(aggregationLabels)s) (avg_over_time(instance:puma_active_connections:sum{%(selector)s}[%(rangeInterval)s]))
      /
      sum by(%(aggregationLabels)s) (instance:puma_max_threads:sum{%(selector)s})
    |||,
    slos: {
      soft: 0.85,
      hard: 0.90,
    },
  }),

  redis_primary_cpu: resourceSaturationPoint({
    title: 'Redis Primary CPU Utilization per Node',
    severity: 's1',
    horizontallyScalable: false,
    appliesTo: ['redis', 'redis-sidekiq', 'redis-cache'],
    description: |||
      Redis Primary CPU Utilization per Node.

      Redis is single-threaded. A single Redis server is only able to scale as far as a single CPU on a single host.
      When the primary Redis service is saturated, major slowdowns should be expected across the application, so avoid if at all
      possible.
    |||,
    grafana_dashboard_uid: 'sat_redis_primary_cpu',
    resourceLabels: ['fqdn'],
    burnRate: '5m',
    query: |||
      (
        rate(redis_cpu_user_seconds_total{%(selector)s}[%(rangeInterval)s])
        +
        rate(redis_cpu_sys_seconds_total{%(selector)s}[%(rangeInterval)s])
      )
      and on (instance) redis_instance_info{role="master"}
    |||,
    slos: {
      soft: 0.70,
      hard: 0.90,
    },
  }),

  redis_secondary_cpu: resourceSaturationPoint({
    title: 'Redis Secondary CPU Utilization per Node',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: ['redis', 'redis-sidekiq', 'redis-cache'],
    description: |||
      Redis Secondary CPU Utilization per Node.

      Redis is single-threaded. A single Redis server is only able to scale as far as a single CPU on a single host.
      CPU saturation on a secondary is not as serious as critical as saturation on a primary, but could lead to
      replication delays.
    |||,
    grafana_dashboard_uid: 'sat_redis_secondary_cpu',
    resourceLabels: ['fqdn'],
    burnRate: '5m',
    query: |||
      (
        rate(redis_cpu_user_seconds_total{%(selector)s}[%(rangeInterval)s])
        +
        rate(redis_cpu_sys_seconds_total{%(selector)s}[%(rangeInterval)s])
      )
      and on (instance) redis_instance_info{role!="master"}
    |||,
    slos: {
      soft: 0.85,
      hard: 0.95,
    },
  }),

  // conntrack saturation may have been the cause of
  // https://gitlab.com/gitlab-com/gl-infra/production/-/issues/2381
  // see https://gitlab.com/gitlab-com/gl-infra/production/-/issues/2381#note_376917724
  // for more details
  nf_conntrack_entries: resourceSaturationPoint({
    title: 'conntrack Entries per Node',
    severity: 's3',
    horizontallyScalable: true,
    appliesTo: { allExcept: ['waf'] },
    description: |||
      Netfilter connection tracking table utilization per node.

      When saturated, new connection attempts (incoming SYN packets) are dropped with no reply, leaving clients to slowly retry (and typically fail again) over the next several seconds.  When packets are being dropped due to this condition, kernel will log the event as: "nf_conntrack: table full, dropping packet".
    |||,
    grafana_dashboard_uid: 'sat_conntrack',
    resourceLabels: ['fqdn', 'instance'],  // Use both labels until https://gitlab.com/gitlab-com/gl-infra/infrastructure/-/issues/10299 arrives
    query: |||
      max_over_time(node_nf_conntrack_entries{%(selector)s}[%(rangeInterval)s])
      /
      node_nf_conntrack_entries_limit{%(selector)s}
    |||,
    slos: {
      soft: 0.95,
      hard: 0.98,
    },
  }),

  // TODO: figure out how k8s management falls into out environment/tier/type/stage/shard labelling
  // taxonomy. These saturation metrics rely on this in order to work
  // See https://gitlab.com/gitlab-com/gl-infra/infrastructure/-/issues/10249 for more details
  // pod_count: resourceSaturationPoint({
  //   title: 'Pod Count Utilization',
  //   description: |||
  //     This measures the HPA that manages our Deployments. If we are running low on
  //     ability to scale up by hitting our maximum HPA Pod allowance, we will have
  //     fully saturated this service.
  //   |||,
  //   grafana_dashboard_uid: 'sat_pod_count',
  //   resourceLabels: ['hpa'],
  //   query: |||
  //     avg_over_time(kube_hpa_status_current_replicas[%(rangeInterval)s])
  //     /
  //     avg_over_time(kube_hpa_spec_max_replicas[%(rangeInterval)s])
  //   |||,
  //   slos: {
  //     soft: 0.70,
  //     hard: 0.90,
  //   },
  // }),

  // TODO: figure out how k8s management falls into out environment/tier/type/stage/shard labelling
  // taxonomy. These saturation metrics rely on this in order to work
  // See https://gitlab.com/gitlab-com/gl-infra/infrastructure/-/issues/10249 for more details
  kube_hpa_instances: resourceSaturationPoint({
    title: 'HPA Instances',
    severity: 's2',
    horizontallyScalable: true,
    appliesTo: ['kube'],
    description: |||
      This measures the HPA that manages our Deployments. If we are running low on
      ability to scale up by hitting our maximum HPA Pod allowance, we will have
      fully saturated this service.
    |||,
    runbook: 'docs/uncategorized/kubernetes.md#hpascalecapability',
    grafana_dashboard_uid: 'sat_kube_hpa_instances',
    resourceLabels: ['hpa'],
    // TODO: keep these resources with the services they're managing, once https://gitlab.com/gitlab-com/gl-infra/infrastructure/-/issues/10249 is resolved
    // do not apply static labels
    staticLabels: {
      type: 'kube',
      tier: 'inf',
      stage: 'main',
    },
    // TODO: remove label-replace ugliness once https://gitlab.com/gitlab-com/gl-infra/infrastructure/-/issues/10249 is resolved
    // TODO: add %(selector)s once https://gitlab.com/gitlab-com/gl-infra/infrastructure/-/issues/10249 is resolved
    query: |||
      label_replace(
        label_replace(
          kube_hpa_status_desired_replicas{%(selector)s, hpa!~"gitlab-sidekiq-(%(ignored_sidekiq_shards)s)-v1"}
          /
          kube_hpa_spec_max_replicas,
          "stage", "cny", "hpa", "gitlab-cny-.*"
        ),
        "type", "$1", "hpa", "gitlab-(?:cny-)?(\\w+)"
      )
    |||,
    queryFormatConfig: {
      // Ignore non-autoscaled shards and throttled shards
      ignored_sidekiq_shards: std.join('|', sidekiqHelpers.shards.listFiltered(function(shard) !shard.autoScaling || shard.urgency == 'throttled')),
    },
    slos: {
      soft: 0.95,
      hard: 0.90,
      alertTriggerDuration: '25m',
    },
  }),

  kube_persistent_volume_claim_inodes: resourceSaturationPoint({
    title: 'Kube Persistent Volume Claim inode Utilisation',
    severity: 's2',
    horizontallyScalable: true,
    appliesTo: ['kube'],
    description: |||
      inode utilization on persistent volume claims.
    |||,
    runbook: 'docs/uncategorized/kubernetes.md',
    grafana_dashboard_uid: 'sat_kube_pvc_inodes',
    resourceLabels: ['persistentvolumeclaim'],
    // TODO: keep these resources with the services they're managing, once https://gitlab.com/gitlab-com/gl-infra/infrastructure/-/issues/10249 is resolved
    // do not apply static labels
    staticLabels: {
      type: 'kube',
      tier: 'inf',
      stage: 'main',
    },
    query: |||
      kubelet_volume_stats_inodes_used
      /
      kubelet_volume_stats_inodes
    |||,
    slos: {
      soft: 0.85,
      hard: 0.90,
    },
  }),

  kube_persistent_volume_claim_disk_space: resourceSaturationPoint({
    title: 'Kube Persistent Volume Claim inode Utilisation',
    severity: 's2',
    horizontallyScalable: true,
    appliesTo: ['kube'],
    description: |||
      disk space utilization on persistent volume claims.
    |||,
    runbook: 'docs/uncategorized/kubernetes.md',
    grafana_dashboard_uid: 'sat_kube_pvc_disk_space',
    resourceLabels: ['persistentvolumeclaim'],
    // TODO: keep these resources with the services they're managing, once https://gitlab.com/gitlab-com/gl-infra/infrastructure/-/issues/10249 is resolved
    // do not apply static labels
    staticLabels: {
      type: 'kube',
      tier: 'inf',
      stage: 'main',
    },
    query: |||
      kubelet_volume_stats_used_bytes
      /
      kubelet_volume_stats_capacity_bytes
    |||,
    slos: {
      soft: 0.85,
      hard: 0.90,
    },
  }),

  praefect_cloudsql_cpu: resourceSaturationPoint({
    title: 'Average CPU Utilization',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: ['monitoring'],
    description: |||
      Average CPU utilization.

      See https://cloud.google.com/monitoring/api/metrics_gcp#gcp-cloudsql for
      more details
    |||,
    grafana_dashboard_uid: 'sat_praefect_cloudsql_cpu',
    resourceLabels: ['database_id'],
    burnRatePeriod: '5m',
    staticLabels: {
      type: 'praefect',
      tier: 'stor',
      stage: 'main',
    },
    query: |||
      avg_over_time(stackdriver_cloudsql_database_cloudsql_googleapis_com_database_cpu_utilization{database_id=~".+:praefect-db.+", %(selector)s}[%(rangeInterval)s])
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),

  kube_container_memory: resourceSaturationPoint({
    title: 'Kube Container Memory Utilization',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: kubeProvisionedServices,
    description: |||
      Records the total memory utilization for containers for this service, as a percentage of
      the memory limit as configured through Kubernetes.
    |||,
    grafana_dashboard_uid: 'sat_kube_container_memory',
    resourceLabels: ['pod', 'container'],
    // burnRatePeriod: '5m',
    query: |||
      container_memory_working_set_bytes:labeled{container!="", container!="POD", %(selector)s}
      /
      (container_spec_memory_limit_bytes:labeled{container!="", container!="POD", %(selector)s} > 0)
    |||,
    slos: {
      soft: 0.90,
      hard: 0.99,
      alertTriggerDuration: '15m',
    },
  }),

  kube_container_cpu: resourceSaturationPoint({
    title: 'Kube Container CPU Utilization',
    severity: 's4',
    horizontallyScalable: true,
    appliesTo: kubeProvisionedServices,
    description: |||
      Kubernetes containers are allocated a share of CPU. When this is exhausted, the container may be thottled.
    |||,
    grafana_dashboard_uid: 'sat_kube_container_cpu',
    resourceLabels: ['pod', 'container'],
    burnRatePeriod: '5m',
    query: |||
      sum by (%(aggregationLabels)s) (
        rate(container_cpu_usage_seconds_total:labeled{container!="", container!="POD", %(selector)s}[%(rangeInterval)s])
      )
      /
      sum by(%(aggregationLabels)s) (
        container_spec_cpu_quota:labeled{container!="", container!="POD", %(selector)s}
        /
        container_spec_cpu_period:labeled{container!="", container!="POD", %(selector)s}
      )
    |||,
    slos: {
      soft: 0.90,
      hard: 0.99,
      alertTriggerDuration: '15m',
    },
  }),

  // Add some helpers. Note that these use :: to "hide" then:

  /**
   * Given a service (identified by `type`) returns a list of resources that
   * are monitored for that type
   */
  listApplicableServicesFor(type)::
    std.filter(function(k) self[k].appliesToService(type), std.objectFields(self)),

  // Iterate over resources, calling the mapping function with (name, definition)
  mapResources(mapFunc)::
    std.map(function(saturationName) mapFunc(saturationName, self[saturationName]), std.objectFields(self)),
}
