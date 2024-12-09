<!-- MARKER: do not edit this section directly. Edit services/service-catalog.yml then run scripts/generate-docs -->

**Table of Contents**

[[_TOC_]]

# Global Code Search Service

* **Alerts**: <https://alerts.gitlab.net/#/alerts?filter=%7Btype%3D%22zoekt%22%2C%20tier%3D%22inf%22%7D>
* **Label**: gitlab-com/gl-infra/production~"Service::Zoekt"

## Logging

* [Rails](https://log.gprd.gitlab.net/goto/15b83f5a97e93af2496072d4aa53105f)
* [Sidekiq](https://log.gprd.gitlab.net/goto/d7e4791e63d2a2b192514ac821c9f14f)

<!-- END_MARKER -->

## Summary

### Quick start

Currently we use Elasticsearch for code search within GitLab. Elasticsearch has turned out to be a poor fit for code search.
In order to solve that we're rolling out new Code Search based on [Zoekt](https://github.com/sourcegraph/zoekt) to select
number of customers as part of this [epic](https://gitlab.com/groups/gitlab-org/-/epics/9404).

### How-to guides

#### Enabling/Disabling Zoekt search

You can prevent Gitlab from using Zoekt integration for searching by unchecking the checkbox `Enable exact code search` under the section `Exact code search configuration` found in the admin [settings](https://gitlab.com/admin/application_settings/advanced_search)(accessed by admins only) `Settings->Search`, but leave the indexing integration itself enabled.
An example of when this is useful is during an incident where users are experiencing slow searches or Zoekt is unresponsive.

#### Enabling/Disabling Zoekt search for specific namespaces

When we rollout Zoekt search for SaaS customers, it is enabled by default. But if a customer wish to get it disabled we can run the following chatops command to disable the Zoekt search specifically for a namespace.

```
  /chatops run feature set --group=root-group-path disable_zoekt_search_for_saas true --production
```

To re-enable it again we can run the following chatops command

```
  /chatops run feature set --group=root-group-path disable_zoekt_search_for_saas false --production
```

#### Evicting namespaces from a Zoekt node

Zoekt has an `eviction` task that runs on a [defined schedule for GitLab.com](https://gitlab.com/gitlab-org/gitlab/-/blob/master/ee/app/services/search/zoekt/scheduling_service.rb#L64). It detects nodes
which are over the watermark limit for disk utilization and removes namespaces until the node
is back under the watermark lower limit. Those namespaces are removed
from the node. The `eviction` task is responsible for removing namespaces. The `dot_com_rollout`
handles adding namespaces to nodes with capacity.

Note: The `eviction` task is currently behind a default enabled feature flag named `zoekt_reallocation_task`

If Zoekt search FF is disabled, but you still see that some nodes misbehave (OOM or disk usage too high
for example), you can run the eviction task manually to evict some of the namespaces from the node:

1. Execute the script in rails console

   ```ruby
   ::Search::Zoekt::SchedulingService.execute(:eviction)
   ```

#### Removing a namespace from the zoekt node manually

If the eviction task returns false or does not relieve pressure on the node,
you can remove a namespace from Zoekt manually.

1. Execute the script in rails console

   ```ruby
   # Find the offending node (gitlab-gitlab-zoekt-1 in this example)
   node = Search::Zoekt::Node.where("metadata @> ?", { name: 'gitlab-gitlab-zoekt-1' }.to_json).order(:last_seen_at).last

   # Find the namespaces and repository sizes on the node
   sizes = {}
   node.indices.each_batch do |batch|
      scope = Namespace.includes(:root_storage_statistics).by_parent(nil).id_in(batch.select(:namespace_id))

      scope.each do |group|
         sizes[group.id] = group.root_storage_statistics&.repository_size || 0
      end
   end
   sorted = sizes.to_a.sort_by { |_k, v| v }

   # Find the largest namespace
   namespace_id = sorted.last[0]
   namespace = Namespace.find(namespace_id)

   # Destroy all `::Search::Zoekt::Replica` records for the namespace
   zoekt_replicas = ::Search::Zoekt::Replica.for_namespace(namespace_id)
   zoekt_replicas.destroy_all
   ```

1. Post namespace_ids on the incident issue as a private comment so there is a record. The Zoekt architecture will handle allocating the namespaces and projects to a new node.

#### Marking a zoekt node as lost

When a Zoekt node PVC is over 80% of usage and evicting or removing namespaces doesn't reduce the usage, you can quickly remove all namespaces from a Zoekt node by manually mark the node as lost. This is a safe operation because the lost node will reregister itself as a new node and the [Zoekt Architecture](https://handbook.gitlab.com/handbook/engineering/architecture/design-documents/code_search_with_zoekt/) will handle allocating all namespaces and projects.

Warning: The new UUID must not exist in the table.

```ruby
node_name = 'gitlab-gitlab-zoekt-29'
uuid = SecureRandom.uuid

Search::Zoekt::Node.by_name(node_name).update_all(uuid: uuid, last_seen_at: 24.hours.ago)
```

#### When to add a Zoekt node

Increase the number of [Zoekt replicas](https://gitlab.com/gitlab-com/gl-infra/k8s-workloads/gitlab-com/-/blob/cda7e4434d3836592b08e16bad8a35705af9f72c/releases/gitlab/values/gprd.yaml.gotmpl#L5) (nodes) by 20% of total capacity if all Zoekt nodes are above 65% of disk utilization. For example, if there are 22 nodes, add 4.4 (4 nodes).

#### Pausing Zoekt indexing

Zoekt indexing can be paused by checking the checkbox `Pause indexing for exact code search` under the section `Exact code search configuration` found in the admin [settings](https://gitlab.com/admin/application_settings/advanced_search)(accessed by admins only) `Settings->Search`. The [jobs are stored in a separate `ZSET`](https://docs.gitlab.com/ee/development/sidekiq/worker_attributes.html#job-pause-control) and re-enqueued when indexing is unpaused. An example
of when this is useful is during an incident when there are a large number of indexing Sidekiq jobs failing.

#### Disabling Zoekt indexing

Zoekt indexing can be completely disabled by unchecking the checkbox `Enable indexing for exact code search` under the section `Exact code search configuration` found in the admin [settings](https://gitlab.com/admin/application_settings/advanced_search)(accessed by admins only) `Settings->Search`. Pausing indexing is the preferred method to halt Zoekt indexing.

WARNING:
Indexed data will be stale after indexing is re-enabled. Reindexing from scratch may be necessary to ensure up to date search results.

#### Limitations

1. Multiple shards and replication are not supported yet. You can follow the progress in <https://gitlab.com/groups/gitlab-org/-/epics/11382>.

## Architecture

### How Zoekt is used

In order to index repositories and provide search functionality we use 1 binary from the Zoekt repository and
1 binary from the gitlab-org repository:

* [`gitlab-zoekt-indexer`](https://gitlab.com/gitlab-org/gitlab-zoekt-indexer) is built using the
[`github.com/sourcegraph/zoekt`](https://github.com/sourcegraph/zoekt) and [`gitlab-org/gitaly`](https://gitlab.com/gitlab-org/gitaly/) libraries.
It is used to receive requests from GitLab and index provided repositories.
* [`zoekt-webserver`](https://github.com/sourcegraph/zoekt/tree/main/cmd/zoekt-webserver) is used to serve search requests. Needs to have access to index files produced by `gitlab-zoekt-indexer`.

### Zoekt API

#### Indexing

For `gitlab-zoekt-indexer` we use `/indexer/index` requests with repository URL and project ID:

```shell
curl -s -XPOST -d '{"CloneUrl":"https://gitlab.com/gitlab-org/gitlab.git","RepoId":278964, "FileSizeLimit": 2097152, "Timeout": "1h", "GitalyConnectionInfo": {"Address": "gitaly.address", "Storage": "default", "Path": "path/gitlab-org/gitlab.git"} }' -H 'Content-Type: application/json' https://zoekt-indexer.url/indexer/index
```

#### Delete

For `gitlab-zoekt-indexer` we use `/indexer/index/:repoId` requests with the project ID:

```shell
curl -s -XDELETE https://zoekt-indexer.url/indexer/index/278964
```

#### Searching

For `zoekt-webserver` we use the `/api/search` endpoint:

```shell
curl -s -XPOST -d '{"Q":"query","RepoIds":[278964],"Opts":{"TotalMaxMatchCount":20,"NumContextLines":1}}' 'https://zoekt-webserver.url/api/search'
```

### Indexer

#### Overview

Indexing happens in two scenarios:

* initial indexing - triggered by adding namespaces
* new events (e.g. git push) - webserver schedules sidekiq jobs that run indexers

#### Triggering indexing

Gitlab application will be scheduling sidekiq jobs. Once a namespace is enabled sidekiq jobs will be scheduled for it. You can always manually retrigger a project to be indexed from the Rails console with `Zoekt::IndexerWorker.perform_async(<project id>)`.

#### Sidekiq jobs

Examples of indexer jobs:

* `ee/app/workers/zoekt/indexer_worker.rb`

Logs available in centralised logging, see [Logging](../logging/README.md)

<!-- ## Performance -->

## Scalability

### How much Zoekt storage do we need

Zoekt index takes about 2.8 times of the source code in the indexed branch (excluding binary files). We also store bare repos as an intermediate step for generating the index files.
This is a significant storage overhead so we plan to optimize this in <https://gitlab.com/gitlab-org/gitlab/-/issues/384722>

<!-- ## Links to further Documentation -->
<!-- ## Availability -->

<!-- ## Durability -->

<!-- ## Security/Compliance -->

## Monitoring

### Dashboards

There are a few dashboards to monitor Zoekt health:

* [Zoekt Health Dashboard](https://log.gprd.gitlab.net/app/r/s/jR5H5): Monitor search and indexing operations
* [Zoekt memory usage](https://thanos-query.ops.gitlab.net/graph?g0.expr=sum(process_resident_memory_bytes%7Benv%3D%22gprd%22,%20container%3D~%22zoekt.*%22%7D)%20by%20(container,%20pod)&g0.tab=0&g0.stacked=0&g0.range_input=2h&g0.max_source_resolution=0s&g0.deduplicate=1&g0.partial_response=0&g0.store_matches=%5B%5D&g0.step_input=60) : View memory utilization for Zoekt containers
* [Zoekt OOM errors](https://thanos.gitlab.net/graph?g0.expr=(sum%20by%20(container%2C%20pod%2C%20environment)%20(kube_pod_container_status_last_terminated_reason%7Benv%3D%22gprd%22%2C%20cluster%3D%22gprd-gitlab-gke%22%2C%20pod%3D~%22gitlab-gitlab-zoekt-%5B0-9%5D%2B%22%2C%20reason%3D%22OOMKilled%22%7D)%0A%20%20%20%20%20%20*%20on%20(container%2C%20pod%2C%20environment)%20group_left%0A%20%20%20%20%20%20sum%20by%20(container%2C%20pod%2C%20environment)%20(changes(kube_pod_container_status_restarts_total%7Benv%3D%22gprd%22%2C%20cluster%3D%22gprd-gitlab-gke%22%2C%20pod%3D~%22gitlab-gitlab-zoekt-%5B0-9%5D%2B%22%7D%5B1m%5D)%20%3E%200))%0A&g0.tab=0&g0.stacked=0&g0.range_input=12h&g0.max_source_resolution=0s&g0.deduplicate=1&g0.partial_response=0&g0.store_matches=%5B%5D): View any Out Of Memory exceptions for Zoekt containrs
* [Zoekt pvc usage](https://dashboards.gitlab.net/goto/tnRv54jSR?orgId=1): View PVC volume capacity for Zoekt nodes
* [Zoekt indexing locks in progress](https://dashboards.gitlab.net/goto/ugHccVjIR?orgId=1): View number of indexing locks (locks are per project)
* [Zoekt Info Dashboard](https://dashboards.gitlab.net/d/search-zoekt/search3a-zoekt-info)

### Kibana logs

GitLab application has a dedicated `zoekt.log` file for Zoekt-related log entries. This will be handled by the standard logging infrastructure. You may also find indexing related errors in `sidekiq.log` and search related errors in `production_json.log`.

As for `gitlab-zoekt-indexer` and `zoekt-webserver`, they write logs to stdout.

## Alerts

### `kube_persistent_volume_claim_disk_space`

[Zoekt architecture](https://handbook.gitlab.com/handbook/engineering/architecture/design-documents/code_search_with_zoekt/) has logic which detects when nodes disk usage is over the limit. Projects will be removed from each node until it the node disk usage under the limit. If the disk space is not coming down quick enough, remove namespaces using the [eviction task](#evicting-namespaces-from-one-zoekt-node-to-another), [remove namepaces manually](#removing-a-namespace-from-the-zoekt-node-manually), or [mark the node as lost a last resort](#marking-a-zoekt-node-as-lost).

WARNING: The PVC disk size must not be increased manually. Zoekt nodes are sized with a specific PVC size and it must remain consistant across all nodes.
