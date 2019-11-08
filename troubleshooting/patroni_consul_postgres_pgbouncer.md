<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [Example](#example)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## High-level summary

Brief summary of interactions between Patroni, Consul, PgBouncer, and our Rails app:

### What *normal* looks like

#### Purpose of each service

* Patroni provides cluster management for Postgres, automating failover of the primary db and reconfiguring replica dbs to follow the new primary db's transaction stream.
* Consul provides shared state and lock management to Patroni.  It also provides quick DNS-based updates to database clients when Patroni nodes fail or change roles.
* PgBouncer provides connection pooling for Postgres.  We have two separate styles of use for PgBouncer:
    * Access to the primary db transits a dedicated pool of PgBouncer hosts, which discover the current Patroni leader (i.e. the primary db) by querying Consul's DNS record `master.patroni.service.consul`.  In turn, database clients access that pool of PgBouncer hosts through a single IP address that is load balanced among the pool members by a Google Internal TCP Loadbalancer.  That load balanced IP address is published as the DNS A record `pgbouncer.int.gprd.gitlab.net`.
    * Access to each of the replica dbs transits 1 of 2 PgBouncer instances running locally on that Patroni host.  Database clients discover the list of available replica db PgBouncer instances by querying Consul's DNS SRV record `db-replica.service.consul`.

#### Interactions between these services

* Patroni uses Consul mainly as a lock manager and as a key-value datastore to hold Patroni cluster metadata.
    * Each Patroni agent must regularly:
        * Fetch the Patroni cluster's state from Consul.
        * Publish its own local node state to Consul.
        * Renew its Consul session lock.
    * If the Patroni leader fails to renew its session lock before the lock's TTL expires, the other Patroni nodes will elect a new leader and trigger a Patroni failover.
* Patroni agent makes REST calls to the local Consul agent.  In turn, the Consul agent makes RPC calls to a Consul server, which is where state is stored.  Consul agents do not locally cache KV data.
* Our Consul topology has 5 Consul servers and several hundred Consul agents.
    * Consul servers: The Consul servers each store state locally, but only 1 (the Consul leader) accepts write requests.  Typically also only the Consul leader accepts read requests.  The non-leader Consul servers exist for redundancy and durability, as each Consul server stores a local copy of the event log.  Consul's CAP bias is to prefer consistency and partition tolerance over availability, but with 5 servers, Consul can lose 2 and remain available.  Unreliable network connectivity can trigger a Consul leader election, which causes Consul to be unavailable until connectivity recovers to the point that a quorum is able to elect a new leader.  Such a Consul outage can in turn cause Patroni to demote its leader and wait for Consul to become available so Patroni can elect a new leader.
    * Consul agents: Every Consul agent participates in a gossip protocol (Serf) that natively provides a distributed node failure detection mechanism.  Whenever one Consul agent probes another and fails to elicit a prompt response, that node announces via gossip that it suspects the buddy it just probed may be down.  That gossip message quickly propagates to all other Consul agents.  Every agent locally logs this event, so we could look on any other host running Consul agent to see roughly when the event occurred.
* We also use Consul to publish via DNS which Patroni node is the leader (i.e. the primary db) and which are healthy replica dbs.

### What *failure modes* are known, and what their symptoms look like

* See #7790, maybe starting with some combination of the issue's description (especially its `Background` section?) and this [Concise summary of RCA so far](https://gitlab.com/gitlab-com/gl-infra/infrastructure/issues/7790#note_215232905).


## Background info: Relationship between Patroni and Consul

### Patroni's purpose

Patroni's job is to provide high availability for Postgres by automatically detecting node failure, promoting a replica to become the new writable primary, and coordinating the switchover for all other replicas to start following transactions from the new primary once they reach the point of divergence between the old and new primary's timelines.

### Consul's purpose

Consul has 2 primary jobs:
* Store Patroni's state data in a highly-available distributed datastore.
* Advertise via DNS to database clients how to connect to a primary or replica database.

### How and why does Patroni interact with Consul as a datastore?

To accomplish its job, Patroni needs to maintain a strongly consistent and highly available representation of the state of all the Patroni cluster's Postgres instances.  It delegates the durable storage of that state data to an external storage service -- what it calls its Distributed Configuration Store (DCS).  Patroni supports several options for this supporting DCS (Consul, Zookeeper, Etcd, and others); in our case, we chose to use Consul.

Patroni stores several kinds of data in its DCS (Consul), such as:
* Who is the current cluster leader? (consul key `service/pg-ha-cluster/leader`)
* Patroni config settings from the `dcs` stanza of patroni.yml. (consul key `service/pg-ha-cluster/config`)
* Each Patroni node periodically self-describes its status (xlog_location, timeline, role, etc.). (consul keys `service/pg-ha-cluster/members/[hostname]`)
* Other ancillary data, including a history of past failover events, metadata about an in-progress failover, whether or not failover is currently paused, etc.

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


## Commands to inspect Patroni's state stored in Consul's key-value (KV) store

Note that all of these commands can be run from *any* host running a Consul agent in the environment you want to inspect (e.g. `gprd`, `gstg`, etc.).  It does not have to be a Patroni host, because all Consul agents participating in the same gossip membership list can make Consul RPC calls.

Who is the current Patroni leader for the Patroni cluster named "pg-ha-cluster"?  The response's `Session` key is deleted if the cluster lock is voluntarily released.  Otherwise it acts as a mutex, set to the session id of the Consul agent running on the current Patroni leader.

```
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

Show all the state data stored in Consul for this Patroni cluster.  This is the same REST call that's run periodically by Patroni's `get_cluster` method.  Note that the `Value` field is always base-64 encoded.  The decoded values are typically either JSON or a plain string.  (Even numeric values are stored as numeric strings, so they are easy to decode and read.)

```
$ curl -s http://127.0.0.1:8500/v1/kv/service/pg-ha-cluster/?recurse=1 | jq .
[
  {
    "LockIndex": 0,
    "Key": "service/pg-ha-cluster/config",
    "Flags": 0,
    "Value": "eyJyZXRyeV90aW1lb3V0IjoxMCwibG9vcF93YWl0IjoxMCwidHRsIjozMCwibWF4aW11bV9sYWdfb25fZmFpbG92ZXIiOjEwNDg1NzYsInBvc3RncmVzcWwiOnsicGFyYW1ldGVycyI6eyJjaGVja3BvaW50X3RpbWVvdXQiOiI1bWluIiwibWF4X2xvY2tzX3Blcl90cmFuc2FjdGlvbiI6MTI4LCJtYXhfcmVwbGljYXRpb25fc2xvdHMiOjMyLCJtYXhfd2FsX3NlbmRlcnMiOjMyLCJ3YWxfbGV2ZWwiOiJyZXBsaWNhIiwiaG90X3N0YW5kYnkiOiJvbiIsIndhbF9rZWVwX3NlZ21lbnRzIjo1MTIsIm1heF93YWxfc2l6ZSI6IjVHQiIsIm1heF9jb25uZWN0aW9ucyI6MzAwfSwidXNlX3BnX3Jld2luZCI6dHJ1ZSwidXNlX3Nsb3RzIjp0cnVlfX0=",
    "CreateIndex": 7839602,
    "ModifyIndex": 30881313
  },

... (output elided for brevity)
```

List just the `Key` field of the Patroni cluster's Consul KV keys.

```
$ curl -s http://127.0.0.1:8500/v1/kv/service/pg-ha-cluster/?recurse=1 | jq -S '.[].Key'
"service/pg-ha-cluster/config"
"service/pg-ha-cluster/failover"
"service/pg-ha-cluster/history"
"service/pg-ha-cluster/initialize"
"service/pg-ha-cluster/leader"
"service/pg-ha-cluster/members/patroni-02-db-gprd.c.gitlab-production.internal"
"service/pg-ha-cluster/members/patroni-03-db-gprd.c.gitlab-production.internal"
"service/pg-ha-cluster/members/patroni-04-db-gprd.c.gitlab-production.internal"
"service/pg-ha-cluster/members/patroni-05-db-gprd.c.gitlab-production.internal"
"service/pg-ha-cluster/members/patroni-06-db-gprd.c.gitlab-production.internal"
"service/pg-ha-cluster/members/patroni-07-db-gprd.c.gitlab-production.internal"
"service/pg-ha-cluster/members/patroni-09-db-gprd.c.gitlab-production.internal"
"service/pg-ha-cluster/members/patroni-11-db-gprd.c.gitlab-production.internal"
"service/pg-ha-cluster/members/patroni-12-db-gprd.c.gitlab-production.internal"
"service/pg-ha-cluster/members/patroni-13-db-gprd.c.gitlab-production.internal"
"service/pg-ha-cluster/members/patroni-14-db-gprd.c.gitlab-production.internal"
"service/pg-ha-cluster/optime/leader"
```

Extract and decode the value of one of the above records.

```
$ curl -s http://127.0.0.1:8500/v1/kv/service/pg-ha-cluster/?recurse=1 | jq -r '.[] | select(.Key == "service/pg-ha-cluster/leader") | .Value' | base64 -d ; echo
patroni-11-db-gprd.c.gitlab-production.internal
```

Or:

```
$ curl -s http://127.0.0.1:8500/v1/kv/service/pg-ha-cluster/leader | jq -r '.[].Value' | base64 -d ; echo
patroni-11-db-gprd.c.gitlab-production.internal
```

Or use the `consul` CLI tool, and let it do the base-64 decoding for you:

```
$ consul kv get service/pg-ha-cluster/leader
patroni-11-db-gprd.c.gitlab-production.internal
```

Does this host's Consul agent have a Consul session?  If so, show its full details.  This shows the complete definition of the "consul session".  Each Patroni agent has one, and the session id acts as a mutex for any other consul KV record that has a `Session` key set.

```
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

List the consul session id for each Patroni agent in this Patroni cluster (`pg-ha-cluster`).  For reference, the TTL and list of health checks are also included.  (Failing the health check or expiring the TTL invalidates the session.)

```
$ curl -s http://127.0.0.1:8500/v1/session/list | jq -c '.[] | { ID, Name, TTL, Checks }' | grep 'pg-ha-cluster' | sort
{"ID":"0e9e66a5-d17a-3543-e389-209c90731209","Name":"pg-ha-cluster-patroni-09-db-gprd.c.gitlab-production.internal","TTL":"15.0s","Checks":["serfHealth"]}
{"ID":"11612889-ec3a-05f0-c2ff-4cc89265dbc7","Name":"pg-ha-cluster-patroni-01-db-gprd.c.gitlab-production.internal","TTL":"15.0s","Checks":["serfHealth"]}
{"ID":"2a789bdf-6a4a-56e5-da70-c9657a37d431","Name":"pg-ha-cluster-patroni-05-db-gprd.c.gitlab-production.internal","TTL":"15.0s","Checks":["serfHealth"]}
{"ID":"30139366-42ad-83d2-9404-4c72dea4dd1e","Name":"pg-ha-cluster-patroni-12-db-gprd.c.gitlab-production.internal","TTL":"15.0s","Checks":["serfHealth"]}
{"ID":"4979adb2-72c5-a747-5e2f-1ab79a156428","Name":"pg-ha-cluster-patroni-07-db-gprd.c.gitlab-production.internal","TTL":"15.0s","Checks":["serfHealth"]}
{"ID":"5a15aa9e-f001-6cc6-34cb-adbf9d7e7b30","Name":"pg-ha-cluster-patroni-04-db-gprd.c.gitlab-production.internal","TTL":"15.0s","Checks":["serfHealth"]}
{"ID":"b5dc0e2c-a0b8-d91d-f662-3ee0ce7b2650","Name":"pg-ha-cluster-patroni-02-db-gprd.c.gitlab-production.internal","TTL":"15.0s","Checks":["serfHealth"]}
{"ID":"c0a201a5-dd25-fa56-9255-c9ac4aaa3b7e","Name":"pg-ha-cluster-patroni-13-db-gprd.c.gitlab-production.internal","TTL":"15.0s","Checks":["serfHealth"]}
{"ID":"d43960da-b464-eac9-493a-c9f6fe62eacc","Name":"pg-ha-cluster-patroni-14-db-gprd.c.gitlab-production.internal","TTL":"15.0s","Checks":["serfHealth"]}
{"ID":"d4927570-aa31-e3c2-6485-3be167c078d8","Name":"pg-ha-cluster-patroni-06-db-gprd.c.gitlab-production.internal","TTL":"15.0s","Checks":["serfHealth"]}
{"ID":"e4bd06bb-b36b-9d3d-7be7-4199f428b8d5","Name":"pg-ha-cluster-patroni-03-db-gprd.c.gitlab-production.internal","TTL":"15.0s","Checks":["serfHealth"]}
{"ID":"ee43c2cf-5b93-08b7-6900-1cf55c9e83b3","Name":"pg-ha-cluster-patroni-11-db-gprd.c.gitlab-production.internal","TTL":"15.0s","Checks":["serfHealth"]}
```

Show which of the above session ids holds the lock as the Patroni leader.

Again, the existence of the `Session` field on this Consul record acts as the mutex.  If the session is invalidated (expires, fails a health check, or is deleted), then the `service/pg-ha-cluster/leader` is unlocked -- meaning no Patroni node holds the Patroni "cluster lock", causing Patroni to start its leader election process.

```
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

$ curl -s http://127.0.0.1:8500/v1/kv/service/pg-ha-cluster/leader | jq -r '.[].Value' | base64 -d ; echo
patroni-11-db-gprd.c.gitlab-production.internal
```

Or:

```
$ consul kv get -detailed service/pg-ha-cluster/leader
CreateIndex      34165794
Flags            0
Key              service/pg-ha-cluster/leader
LockIndex        1
ModifyIndex      34165794
Session          ee43c2cf-5b93-08b7-6900-1cf55c9e83b3
Value            patroni-11-db-gprd.c.gitlab-production.internal
```

