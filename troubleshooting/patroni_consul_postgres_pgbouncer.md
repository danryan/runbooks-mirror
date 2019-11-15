<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [High-level summary](#high-level-summary)
- [Where do the components run?](#where-do-the-components-run)
- [Links to external docs](#links-to-external-docs)
- [Quick reference commands](#quick-reference-commands)
  - [Consul REST API: Commands to inspect/explore Patroni's state stored in Consul's key-value (KV) store](#consul-rest-api-commands-to-inspectexplore-patronis-state-stored-in-consuls-key-value-kv-store)
  - [Internal Loadbalancer (ILB)](#internal-loadbalancer-ilb)
- [Background details](#background-details)
  - [Purpose of each service](#purpose-of-each-service)
  - [Normal healthy interactions between these services](#normal-healthy-interactions-between-these-services)
  - [What *failure modes* are known, and what their symptoms look like](#what-failure-modes-are-known-and-what-their-symptoms-look-like)
- [FAQ (more background info)](#faq-more-background-info)
  - [What is Patroni's purpose?](#what-is-patronis-purpose)
  - [What is Consul's purpose?](#what-is-consuls-purpose)
  - [How and why does Patroni interact with Consul as a datastore?](#how-and-why-does-patroni-interact-with-consul-as-a-datastore)
  - [What is the difference between the Patroni leader and the Consul leader?](#what-is-the-difference-between-the-patroni-leader-and-the-consul-leader)
  - [Why use one database (Consul) to manage another database (Postgres)?](#why-use-one-database-consul-to-manage-another-database-postgres)
  - [How does Consul balance consistency versus availability?](#how-does-consul-balance-consistency-versus-availability)
- [Details of how Patroni uses Consul](#details-of-how-patroni-uses-consul)
  - [The Patroni "loop": How do Patroni's calls to Consul allow Patroni to decide which Postgres instance to treat as the primary db (and when to failover and promote a different Postgres instance to become primary)?](#the-patroni-loop-how-do-patronis-calls-to-consul-allow-patroni-to-decide-which-postgres-instance-to-treat-as-the-primary-db-and-when-to-failover-and-promote-a-different-postgres-instance-to-become-primary)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->


## High-level summary

Brief summary of how Postgres database access is supported by Patroni, Consul, PgBouncer, and our Rails app:
* Postgres is our relational database.
  * Currently we have 1 writable primary instance and several read-only replica instances of Postgres.
  * The replica dbs handle read-only queries and act as failover candidates in case the primary db becomes unavailable (e.g. unreachable, unresponsive) or concerned about possible split-brain (e.g. unable to see/update Patroni cluster state).
* Patroni coordinates failover when the primary Postgres instance becomes unavailable.
  * Patroni stores its cluster state in Consul.
  * A Patroni agent runs on each Postgres host, monitoring that local Postgres instance and interacting with Consul to check cluster state and publish its own state.
* Database clients (Rails, Sidekiq, etc.) discover Postgres through Consul service discovery and access it through PgBouncer (a connection pooler).
  * PgBouncer is a connection pooling proxy in front of Postgres.  Having thousands of clients connected directly to Postgres causes significant performance overhead.  To avoid this penalty, PgBouncer dynamically maps thousands of client connections to a few hundred db sessions.
  * Consul advertises each PgBouncer instance as a proxy for a corresponding Postgres instance.
  * Because PgBouncer itself is single-threaded and CPU-bound, it can use at most 1 vCPU, so we run multiple PgBouncer instances in front of each Postgres instance to avoid CPU starvation.
  * Database clients discover the IP+port of the available PgBouncer instances by sending DNS queries to a local Consul agent.
* Currently we use dedicated PgBouncer VMs for accessing the primary db, rather than local PgBouncer processes on the db host (as we do for the replica dbs).
  * The primary db gets more traffic than any one replica db.
  * PgBouncer appears to be more CPU-efficient on dedicated VMs than when running on the primary db host.  We have a couple untested hypotheses as to why.
  * The primary db's PgBouncer VMs share a virtual IP address (a Google TCP Internal Load Balancer VIP).  That ILB VIP is what Consul advertises to database clients as the primary db IP.

See [here](#background-details) and [here](#faq-more-background-info) for more details on the purpose, behaviors, and interactions of each service.


## Where do the components run?

| Service/component                 | Chef role                                 | Hostname pattern            | Port (Protocol)                                                       |
| --------------------------------- | ----------------------------------------- | --------------------------- | --------------------------------------------------------------------- |
| Postgres                          | gprd-base-db-patroni                      | patroni-{01..NN}-db-gprd    | 5432 (Pgsql)                                                          |
| PgBouncer for primary db          | gprd-base-db-pgbouncer                    | pgbouncer-{01..NN}-db-gprd  | 6432 (Pgsql)                                                          |
| PgBouncer for replica dbs         | Same as Postgres                          | Same as Postgres            | 6432 (Pgsql), 6433 (Pgsql)                                            |
| Patroni agent                     | Same as Postgres                          | Same as Postgres            | 8009 (REST)                                                           |
| Consul agent                      | gprd-base (recipe `gitlab_consul::agent`) | Nearly all Chef-managed VMs | 8600 (DNS), 8500 (REST), 8301 (Serf LAN)                              |
| Consul server                     | gprd-infra-consul                         | consul-{01..NN}-inf-gprd    | 8600 (DNS), 8500 (REST), 8301 (Serf LAN), 8302 (Serf WAN), 8300 (RPC) |

In addition to the above Chef-managed services, we use a [Google TCP Internal Loadbalancer (ILB)](https://cloud.google.com/load-balancing/docs/internal/)
to provide a single virtual IP address for the pool of PgBouncer instances for the primary db.  This allows clients to treat a pool of PgBouncers as a single endpoint.

Notes about the ILB:
* A Google TCP/UDP Internal Loadbalancer (ILB) is *not* an inline device in the network path.
* Instead, ILB is part of the control plane of the software defined network within a single geographic region.
* All backends (i.e. PgBouncer VMs) share the IP address of the ILB's forwarding rule, and within the VPC network, each TCP/UDP connection is routed to one of those backends.
* Backend instances contact the metadata server (metadata.google.internal) to generate local routes to accept traffic for the ILB's IP address.


## Links to external docs

* [Postgres docs](https://www.postgresql.org/docs/current/index.html) (remember to choose the appropriate version)
* [PgBouncer docs](https://www.pgbouncer.org/faq.html)
* Patroni:
  * [Top-level docs](https://patroni.readthedocs.io/en/latest/)
  * [Explanation of static versus dynamic config settings](https://patroni.readthedocs.io/en/latest/dynamic_configuration.html)
  * [List of all config settings](https://patroni.readthedocs.io/en/latest/SETTINGS.html)
* Consul:
  * [Consul CLI commands](https://www.consul.io/docs/commands/index.html)
  * [Consul Glossary](https://www.consul.io/docs/glossary.html)
  * [Consul Internals](https://www.consul.io/docs/internals/index.html)
* [Google TCP/UDP Internal Loadbalancer (ILB)](https://cloud.google.com/load-balancing/docs/internal/)
  * [List of our load balancers in GCP console web UI](https://console.cloud.google.com/net-services/loadbalancing/loadBalancers/list)


## Quick reference commands


### Consul REST API: Commands to inspect/explore Patroni's state stored in Consul's key-value (KV) store

Note that all of these commands can be run from *any* host running a Consul agent in the environment you want to inspect (e.g. `gprd`, `gstg`, etc.).
It does not have to be a Patroni host, because all Consul agents participating in the same gossip membership list can make Consul RPC calls.

Who is the current Patroni leader for the Patroni cluster named "pg-ha-cluster"?

**Note:** The response's `Session` key is deleted if the cluster lock is voluntarily released.  It acts as a mutex, indicating the session id of the Consul agent running on the current Patroni leader.

```shell
$ curl -s http://127.0.0.1:8500/v1/kv/service/pg-ha-cluster/leader | jq .
[
  {
    "LockIndex": 1,
    "Key": "service/pg-ha-cluster/leader",
    "Flags": 0,
    "Value": "cGF0cm9uaS0xMS1kYi1ncHJkLmMuZ2l0bGFiLXByb2R1Y3Rpb24uaW50ZXJuYWw=",
    "Session": "ee43c2cf-5b93-08b7-6900-1cf55c9e83b3",
    "CreateIndex": 34165794,
    "ModifyIndex": 34165794
  }
]
```

Show all the state data stored in Consul for this Patroni cluster.

**Note:** This is the same REST call that's run periodically by Patroni's `get_cluster` method.  The `Value` field is always base-64 encoded.  The decoded values are typically either JSON or a plain strings.

```shell
$ curl -s http://127.0.0.1:8500/v1/kv/service/pg-ha-cluster/?recurse=1 | jq .
```

List just the `Key` field of the Patroni cluster's Consul KV keys.

```shell
$ curl -s http://127.0.0.1:8500/v1/kv/service/pg-ha-cluster/?recurse=1 | jq -S '.[].Key'
```

Extract and decode the value of one of the above records.

```shell
$ curl -s http://127.0.0.1:8500/v1/kv/service/pg-ha-cluster/leader | jq -r '.[].Value' | base64 -d ; echo
```

Or use the `consul` CLI tool, and let it do the base-64 decoding for you.

```shell
$ consul kv get -detailed service/pg-ha-cluster/leader
```

Does this host's Consul agent have a Consul session?  If so, show its full details.

**Notes:**
* This shows the complete definition of a "consul session".
* Each Patroni agent has its own session.
* A consul agent can use its session `ID` as an advisory lock (mutex) on any consul KV record.  A session can claim exclusive ownership of that record by setting the record's `Session` attribute with its own `ID` value.  When the session is invalidated/expired, the lock is automatically released.
* This locking mechanism is how Patroni uses Consul to ensure that only one node is the Patroni leader (represented by the consul KV record "service/[cluster_name]/leader").

```shell
$ curl -s http://127.0.0.1:8500/v1/session/node/$( hostname -s ) | jq .
[
  {
    "ID": "0e9e66a5-d17a-3543-e389-209c90731209",
    "Name": "pg-ha-cluster-patroni-09-db-gprd.c.gitlab-production.internal",
    "Node": "patroni-09-db-gprd",
    "Checks": [
      "serfHealth"
    ],
    "LockDelay": 1000000,
    "Behavior": "delete",
    "TTL": "15.0s",
    "CreateIndex": 32308118,
    "ModifyIndex": 32308118
  }
]
```

List the consul session id for each Patroni agent in this Patroni cluster (`pg-ha-cluster`).

**Notes:**
* Failing the health check or expiring the TTL invalidates the session.  If that happens to the Patroni leader, it loses the cluster-lock, causing a failover.
* The TTL reported here is always half the value specified in the Patroni config, because Patroni divides that configured value by 2 before setting it in Consul.

```shell
$ curl -s http://127.0.0.1:8500/v1/session/list | jq -c '.[] | { ID, Name, TTL, Checks }' | grep 'pg-ha-cluster' | sort
```

Show which of the above session ids holds the lock as the Patroni leader.

Again, the existence of the `Session` field on this Consul record acts as the mutex.  If the session is invalidated (expires, fails a health check, or is deleted), then the `service/pg-ha-cluster/leader` is unlocked -- meaning no Patroni node holds the Patroni "cluster lock", causing Patroni to start its leader election process.

```
$ curl -s http://127.0.0.1:8500/v1/kv/service/pg-ha-cluster/leader | jq -r '.[].Value' | base64 -d ; echo

Or

$ consul kv get service/pg-ha-cluster/leader
```


### Internal Loadbalancer (ILB)

Unlike other components, the ILB is not a service/process/instance.  It is just a set of network routing rules, with no inline host or device acting as a proxy.  It is purely configuration in the network control plane.

A [Google Internal TCP/UDP Load Balancer](//cloud.google.com/load-balancing/docs/internal/) consists of the following components:
 - Forwarding rule, which owns the IP address of the load balancer (shared by all backends for routing purposes)
 - Backend Service, which contains instance-groups and/or instances (i.e. pool members)
 - Health check, for probing each backend instance

Here are `gcloud` commands for inspecting the above components of the ILB.
Navigating the [GCP Console web UI](https://console.cloud.google.com/net-services/loadbalancing/loadBalancers/list) is also intuitive.

Find and show the internal loadbalancer's forwarding rule.

```shell
$ gcloud --project='gitlab-production' compute forwarding-rules list | egrep 'NAME|pgbouncer'
$ gcloud --project='gitlab-production' compute forwarding-rules describe --region=us-east1 gprd-gcp-tcp-lb-internal-pgbouncer
```

Find and show the internal loadbalancer's target backend service.

```shell
$ gcloud --project='gitlab-production' compute backend-services list --filter="name~'pgbouncer'"
$ gcloud --project='gitlab-production' compute backend-services describe gprd-pgbouncer-regional --region='us-east1'
```

Find and show the internal loadbalancer's health check.

```shell
$ gcloud --project='gitlab-production' compute health-checks list | egrep 'NAME|pgbouncer'
$ gcloud --project='gitlab-production' compute health-checks describe gprd-pgbouncer-http
```

Show the latest results of health-checks against each of the backend-service's backends (i.e. the zone-specific instance-groups).

```shell
$ gcloud --project='gitlab-production' compute backend-services get-health gprd-pgbouncer-regional --region='us-east1'
```

Show that backend service's instance groups.

```shell
$ gcloud --project='gitlab-production' compute instance-groups list | egrep 'NAME|pgbouncer'
```

Describe those instance-groups.

```shell
$ ( for ZONE in us-east1-{b,c,d} ; do export INSTANCE_GROUP="gprd-pgbouncer-${ZONE}" ; echo -e "\nInstance-group: ${INSTANCE_GROUP}" ; gcloud --project='gitlab-production' compute instance-groups describe "${INSTANCE_GROUP}" --zone="${ZONE}" ; done )
```

List the instances in those instance-groups.

```shell
$ ( for ZONE in us-east1-{b,c,d} ; do export INSTANCE_GROUP="gprd-pgbouncer-${ZONE}" ; echo -e "\nInstance-group: ${INSTANCE_GROUP}" ; gcloud --project='gitlab-production' compute instance-groups list-instances "${INSTANCE_GROUP}" --zone="${ZONE}" ; done )
```

## Background details

### Purpose of each service

* Patroni provides cluster management for Postgres, automating failover of the primary db and reconfiguring replica dbs to follow the new primary db's transaction stream.
* Consul provides shared state and lock management to Patroni.  It also provides DNS-based service discovery, so database clients can learn when Patroni nodes fail or change roles.
* PgBouncer provides connection pooling for Postgres.  We have two separate styles of use for PgBouncer:
    * Access to the primary db transits a dedicated pool of PgBouncer hosts, which discover the current Patroni leader (i.e. the primary db) by querying Consul's DNS record `master.patroni.service.consul`.  In turn, database clients access that pool of PgBouncer hosts through a single IP address that is load balanced among the pool members by a Google Internal TCP Loadbalancer.  That load balanced IP address is published as the DNS A record `pgbouncer.int.gprd.gitlab.net`.
    * Access to each of the replica dbs transits either of 2 PgBouncer instances running locally on each Patroni host.  Database clients discover the list of available replica db PgBouncer instances by querying Consul's DNS `SRV` records for `db-replica.service.consul`.  For historical reasons (prior to running multiple PgBouncers per replica db), Consul also publishes DNS `A` records for `replica.patroni.service.consul` pointing to the 1st PgBouncer instance (the one bound to port 6432).

### Normal healthy interactions between these services

* Patroni uses Consul mainly as a lock manager and as a key-value datastore to hold Patroni cluster metadata.
    * Each Patroni agent must regularly:
        * Fetch the Patroni cluster's state from Consul.
        * Publish its own local node state to Consul.
        * Renew its Consul session lock.
    * If the Patroni leader fails to renew its session lock before the lock's TTL expires, the other Patroni nodes will elect a new leader and trigger a Patroni failover.
* Patroni agent makes REST calls to the local Consul agent.
  * To build a response, the Consul agent makes RPC calls to a Consul server, which is where state data is stored.  Consul agents do not locally cache KV data.
* Our Consul topology has 5 Consul servers and several hundred Consul agents.
    * **Consul servers:**
      * The Consul servers each store state locally, but only 1 (the Consul leader) accepts write requests.  Typically also only the Consul leader accepts read requests.
      * The non-leader Consul servers exist for redundancy and durability, as each Consul server stores a local copy of the event log.
      * Consul's CAP bias is to prefer consistency over availability, but with 5 servers, Consul can lose 2 and remain available.
      * Unreliable network connectivity can trigger a Consul leader election, which causes Consul to be unavailable until connectivity recovers to the point that a quorum is able to elect a new leader.  Such a Consul outage can in turn potentially cause Patroni to demote its leader and wait for Consul to become available so Patroni can elect a new leader.
    * **Consul agents:**
      * Every Consul agent participates in a gossip protocol (Serf) that natively provides a distributed node failure detection mechanism.
      * Whenever one Consul agent probes another and fails to elicit a prompt response, the probing node announces via gossip that it suspects the buddy it just probed may be down.  That gossip message quickly propagates to all other Consul agents.
      * Every agent locally logs this event, so we could look on any other host running Consul agent to see roughly when the event occurred.
      * This has proven to be a reliable detector for intermittent partial network outages in GCP's infrastructure.
* We also use Consul to publish via DNS which Patroni node is the leader (i.e. the primary db) and which are healthy replica dbs.
  * Database clients (e.g. Rails app instances) periodically query their host's local Consul agent via DNS to discover the list of available databases.  This list actually refers to PgBouncer instances, which proxy to Postgres itself.
  * If Consul's list of available dbs changes, our Rails app updates its internal database connection pool accordingly.


### What *failure modes* are known, and what their symptoms look like

* See #7790, maybe starting with some combination of the issue's description (especially its `Background` section?) and this [Concise summary of RCA so far](https://gitlab.com/gitlab-com/gl-infra/infrastructure/issues/7790#note_215232905).


## FAQ (more background info)

### What is Patroni's purpose?

Patroni's job is to provide high availability for Postgres by automatically detecting node failure, promoting a replica to become the new writable primary, and coordinating the switchover for all other replicas to start following transactions from the new primary once they reach the point of divergence between the old and new primary's timelines.

### What is Consul's purpose?

Consul has 2 primary jobs:
* Store Patroni's state data in a highly-available distributed datastore.
* Advertise via DNS to database clients how to connect to a primary or replica database.

### How and why does Patroni interact with Consul as a datastore?

To accomplish its job, Patroni needs to maintain a strongly consistent and highly available representation of the state of all the Patroni cluster's Postgres instances.  It delegates the durable storage of that state data to an external storage service -- what it calls its Distributed Configuration Store (DCS).  Patroni supports several options for this DCS (Consul, Zookeeper, Etcd, and others); in our case, we chose to use Consul.

Patroni stores several kinds of data in its DCS (Consul), such as:
* Who is the current cluster leader? (consul key `service/pg-ha-cluster/leader`)
* Patroni config settings from the `dcs` stanza of patroni.yml. (consul key `service/pg-ha-cluster/config`)
* Each Patroni node periodically self-describes its status (xlog_location, timeline, role, etc.). (consul keys `service/pg-ha-cluster/members/[hostname]`)
* Other ancillary data, including a history of past failover events, metadata about an in-progress failover, whether or not failover is currently paused, etc.

*Warning:* If you need to manually `PAUSE` Patroni (i.e. prevent failover even if the primary starts failing health checks), a Chef run an *any* Patroni node will revert that pause.  Chef tells the Patroni agent to force the `dcs` settings in patroni.yml to overwrite any conflicting settings stored in Consul, and that scope unfortunately includes the consul key used for pausing failovers.  So to pause Patroni (e.g. for maintenance), we must first stop Chef on *all* Patroni hosts.

The Consul agent does not locally cache any of the above data.  Every time the Patroni agent asks the local Consul agent to read or write this data, the Consul agent must synchronously make RPC calls to a Consul server.  The Patroni agent's REST call to the Consul agent can timeout or fail if Consul agent's RPC call to Consul server stalls or fails.  (This has proven to be a common failure mode on GCP due to transient network connectivity loss.)

### What is the difference between the Patroni leader and the Consul leader?

The Patroni leader is the Patroni agent corresponding to the writable Postgres database (a.k.a. the primary Postgres db).  All other Patroni nodes correspond to read-only replica Postgres databases that asynchronously replay transaction logs received from the primary Postgres database.

The Consul leader is whichever one of the Consul servers is currently accepting writes.  Consul has its own internal leader-election process, independent of Patroni.

### Why use one database (Consul) to manage another database (Postgres)?

Patroni uses Consul to provide high availability to Postgres through automated failover.

Postgres and Consul are both databases, but they have different strengths and weaknesses.  Consul excels at storing a small amount of data, providing strong consistency guarantees while tolerating the loss of potentially multiple replicas.  But Consul is not designed to handle a high write rate, and it provides just basic key-value storage.  In contrast, Postgres is a much more featureful relational database and supports many concurrent writers.  While Postgres natively provides replication, it does not natively provide an automated failover mechanism.

For Patroni to provide high availability (automated failover) to Postgres, it needs all Patroni agents to have a consistent view of the Patroni cluster state (i.e. who is the current leader, how stale is each replica, etc.).  Patroni stores that state in its DCS (which for us is Consul), with the expectation that writes are durable and reads are strongly consistent.

### How does Consul balance consistency versus availability?

Consul prefers consistency over availability.  When failure conditions such as node loss or network partitions force Consul to choose between consistency and availability, Consul prefers to stop accepting writes and reads until a quorum of Consul server nodes is again reached.  This avoids split-brain.  To reduce the likelihood of losing quorum, Consul supports a peer group of up to 11 servers, but most production deployments use 3 or 5 (which tolerates the loss of 1 or 2 nodes respectively).

As is typical, in production we run 5 hosts as Consul servers to act as the datastore, and we run a Consul agent on every other host that need to read or write data stored on the Consul servers.

The Consul servers participate in a [strongly consistent consensus protocol (RAFT)](https://www.consul.io/docs/internals/consensus.html) for leader election.  Only the current leader is allowed to accept writes, so that all writes are serializable.  These logged writes are replicated to the other Consul servers; at least a majority (quorum) of Consul servers must receive the new log entry for the write to be considered successful (i.e. guaranteed to be present if a new leader is elected).  If the current leader fails, Consul will stop accepting new writes until the surviving quorum of peers elect a new leader (which may take several seconds).  Typically read requests are also handled by the Consul leader, again to provide strong consistency guarantees, but that is tunable.  If a non-leader consul server receives a read request, it will forward that call to the current Consul leader.

Only the Consul servers participate as peers in the strongly-consistent RAFT protocol.  But all Consul agents participate in a [weakly-consistent gossip protocol (SERF)](https://www.consul.io/docs/internals/gossip.html).  This supports automatic node discovery and provides distributed node failure detection.


## Details of how Patroni uses Consul

### The Patroni "loop": How do Patroni's calls to Consul allow Patroni to decide which Postgres instance to treat as the primary db (and when to failover and promote a different Postgres instance to become primary)?

Each Patroni agent (whether replica or primary) periodically interacts with Consul to:
* Fetch the most recently published status of its cluster peers.
* Publish its own current state metadata.
* Affirm its liveness by renewing its consul session (which quickly auto-expires without these renewals).

If Patroni fails one of these REST calls to Consul agent, the failed call can be retried for up to its configured `retry_timeout` deadline (currently 10 seconds).  For the Patroni leader (i.e. the Patroni agent whose Postgres instance is currently the writable primary db), if that retry deadline is reached, Patroni will initiate failover by voluntarily releasing the Patroni cluster lock.

Similarly, if the Patroni leader's loop takes long enough to complete that its consul session expires (TTL is currently 15 seconds), then it involuntarily loses the cluster lock, which also initiates failover.

Another way for Patroni's leader to involuntarily lose its cluster lock is if Consul's "serfCheck" health check fails for that host's Consul agent.  SERF is Consul's gossip protocol.  It acts as a mechanism for automatic peer discovery and failure detection (as well as providing a medium for asynchronous eventually-consistent information sharing).  Every host running a Consul agent participates.  (The `gprd` environment runs 288 agents, as of 2019-09-04.)  Each of those agents intermittently tries to connect to a random subset of other agents, and if that attempt fails, it announces that target as being suspected of being down.  That agent has a limit window of time to actively refute that suspicion.  Meanwhile, other agents will "dogpile" on health-checking the suspected failed agent, and if they concur that the agent is down, the window for refutation shortens (to reduce time to detect a legitimate failure).  After the refutation window expires, the Consul server can mark that Consul agent as failed.  If that "serfCheck" failure designation is applied to the host that's currently the Patroni leader, then this immediately invalidates the Patroni agent's consul session (which, as described above is the mutex underlying the Patroni "cluster lock").  In summary, any host's consul agent can flag the Patroni leader's Consul agent as potentially down, and if it does not promptly refute that claim, Patroni will initiate a failover -- all because Consul's "serfCheck" healthiness is part of Patroni's contract for maintaining the validity of its consul session.

In any case, Patroni's leader election protocol allows a period of time for all replicas to catch up on any transaction data they had received but not yet applied, and at the end of the grace period, the freshest replica will be promoted to become the new primary.
