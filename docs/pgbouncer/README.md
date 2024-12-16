<!-- MARKER: do not edit this section directly. Edit services/service-catalog.yml then run scripts/generate-docs -->

**Table of Contents**

[[_TOC_]]

# PGBouncer Primary Database Pool Service

* [Service Overview](https://dashboards.gitlab.net/d/pgbouncer-main/pgbouncer-overview)
* **Alerts**: <https://alerts.gitlab.net/#/alerts?filter=%7Btype%3D%22pgbouncer%22%2C%20tier%3D%22db%22%7D>
* **Label**: gitlab-com/gl-infra/production~"Service::Pgbouncer"

## Logging

* [pgbouncer](https://log.gprd.gitlab.net/goto/3fb9391e5ef07b47aac2fce6fda175d9)
* [system](https://log.gprd.gitlab.net/goto/ae311f6f133cc1c45b62541977081043)

## Troubleshooting Pointers

* [Interacting with Consul](../consul/interaction.md)
* [Disaster Recovery Gameday Schedule](../disaster-recovery/gameday-schedule.md)
* [Measuring Recovery Activities](../disaster-recovery/recovery-measurements.md)
* [Zonal and Regional Recovery Guide](../disaster-recovery/recovery.md)
* [../frontend/gitlab-com-is-down.md](../frontend/gitlab-com-is-down.md)
* [Recovering from CI Patroni cluster lagging too much or becoming completely broken](../patroni-ci/recovering_patroni_ci_intense_lagging_or_replication_stopped.md)
* [Steps to create (or recreate) a Standby CLuster using a Snapshot from a Production cluster as Master cluster (instead of pg_basebackup)](../patroni/build_cluster_from_snapshot.md)
* [Log analysis on PostgreSQL, Pgbouncer, Patroni and consul Runbook](../patroni/log_analysis.md)
* [OS Upgrade Reference Architecture](../patroni/os_upgrade_reference_architecture.md)
* [Patroni Cluster Management](../patroni/patroni-management.md)
* [../patroni/performance-degradation-troubleshooting.md](../patroni/performance-degradation-troubleshooting.md)
* [PostgreSQL HA](../patroni/pg-ha.md)
* [Pg_repack using gitlab-pgrepack](../patroni/pg_repack.md)
* [Diagnosing long running transactions](../patroni/postgres-long-running-transaction.md)
* [../patroni/postgres.md](../patroni/postgres.md)
* [../patroni/postgresql-buffermapping-lwlock-contention.md](../patroni/postgresql-buffermapping-lwlock-contention.md)
* [How to evaluate load from queries](../patroni/postgresql-query-load-evaluation.md)
* [How to provision the benchmark environment](../patroni/provisioning_bench_env.md)
* [Rotating Rails' PostgreSQL password](../patroni/rotating-rails-postgresql-password.md)
* [Handling Unhealthy Patroni Replica](../patroni/unhealthy_patroni_node_handling.md)
* [Roles/Users grants and permission Runbook](../patroni/user_grants_permission.md)
* [patroni-consul-postgres-pgbouncer-interactions.md](patroni-consul-postgres-pgbouncer-interactions.md)
* [Add a new PgBouncer instance](pgbouncer-add-instance.md)
* [pgbouncer-applications.md](pgbouncer-applications.md)
* [PgBouncer connection management and troubleshooting](pgbouncer-connections.md)
* [Removing a PgBouncer instance](pgbouncer-remove-instance.md)
* [Sidekiq or Web/API is using most of its PgBouncer connections](pgbouncer-saturation.md)
* [service-pgbouncer.md](service-pgbouncer.md)
* [Postgres Replicas](../postgres-dr-delayed/postgres-dr-replicas.md)
* [Database Connection Pool Saturation](../registry/app-db-conn-pool-saturation.md)
* [Container Registry database post-deployment migrations](../registry/db-post-deployment-migrations.md)
* [Pull mirror overdue queue is too large](../sidekiq/large-pull-mirror-queue.md)
* [A survival guide for SREs to working with Sidekiq at GitLab](../sidekiq/sidekiq-survival-guide-for-sres.md)
* [How to use flamegraphs for performance profiling](../tutorials/how_to_use_flamegraphs_for_perf_profiling.md)
<!-- END_MARKER -->

# PgBouncer

PgBouncer is a connection pooler for PostgreSQL, allowing many frontend
connections to re-use existing PostgreSQL backend connections. For example, you
can map 1024 PgBouncer connections to 100 PostgreSQL connections.

For more information refer to [PgBouncer's
website](http://pgbouncer.github.io/).

## Pooling Mode

PgBouncer has three pooling "aggressiveness" settings that uses to determine how
it manages its pooled connections:

* Session Pooling: When a (postgres) client connects, a server connection will
  be assigned to it until it disconnects. All Postgres features are available.
* Transaction Pooling: A server connection is assigned to a client only during a
  transaction. Session based-features like `SET statement_timeout = 0` cannot be
  relied on in this mode.
* Statement Pooling: A server connection per statement. This means that only
  single-statement (i.e. "autocommit") transactions are allowed.

Given that our postgres clients (sidekiq nodes, web nodes, etc) use long-lived
connections to execute transactions from different requests spread over time,
session pooling is inefficient for our purposes. And evidently our application
logic doesn't work in autocommit mode. Therefore, we use Transaction Pooling.

For more details, see <https://www.pgbouncer.org/features.html>

## PgBouncer Hosts

![architecture overview of pgbouncer](./img/overview.png)

* Primary (read-write) has 3 dedicated hosts in front of the database host, since it serving more traffic.
* Replica (read-only) had 3 PgBouncer processes running on the same host that is running the  PostgreSQL process.

PgBouncer is configured via omnibus via these [config options](https://gitlab.com/gitlab-org/omnibus-gitlab/blob/34b92e63f765a4d74c3384e3c7c08a4750f9d2c5/files/gitlab-config-template/gitlab.rb.template#L2185-2290).
The PgBouncer configuration files are located in `/var/opt/gitlab/pgbouncer`,
including a `database.ini` file from consul, the port PgBouncer listens on is 6432.

## PgBouncer Commands

PgBouncer is controlled using systemd (`systemctl`). Note that restarting
PgBouncer will terminate existing connections immediately, possibly leading to
application errors.

It is also possible to connect directly to PgBouncer:

* `sudo pgb-console`

You can also control and show statistics for PgBouncer when connected to it
using its own set of commands. See
<http://pgbouncer.github.io/usage.html#admin-console> for more information.

## Applying Changes

Almost all settings of PgBouncer can be managed by editing the relevant Chef
roles:

* roles/[env]-base-db-pgbouncer-common.json
* roles/[env]-base-db-pgbouncer-pool.json
* roles/[env]-base-db-pgbouncer-sidekiq.json
* roles/[env]-base-db-pgbouncer-sidekiq-ci.json
* roles/[env]-base-db-pgbouncer.json
* roles/[env]-base-db-pgbouncer-ci.json

Most settings only require a reload of pgbouncer and will not cause an
interruption of service. To manually reload, run `sudo systemctl reload pgbouncer`

To manually restart, run `sudo systemctl restart pgbouncer`.
**Note:** This will cause an interruption to existing connections.

## Healthcheck

In gprd and gstg, clients access pgbouncer via an internal load balancer (ILB)
named ENV-pgbouncer-regional (for primary traffic) and ENV-pgbouncer-sidekiq-regional
for sidekiq.

Before Dec 2019 there was an HTTP-based healthcheck (with consul used to limit
active nodes to N-1) called pgbouncer-leader.  If you're looking for that, it has
been removed.

The healthcheck now is a simple TCP check to the pgbouncer port.  This causes
pgbouncer logs about connections to 'nodb' by 'nouser'; do not be alarmed by these.

<!-- ## Summary -->

<!-- ## Architecture -->

<!-- ## Performance -->

<!-- ## Scalability -->

<!-- ## Availability -->

<!-- ## Durability -->

<!-- ## Security/Compliance -->

<!-- ## Monitoring/Alerting -->

<!-- ## Links to further Documentation -->
