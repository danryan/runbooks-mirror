# Kubernetes

**Table of Contents**

[TOC]

GitLab utilizes Google Kubernetes Engine (GKE) for running Kubernetes provided
resources.

Groups/Repositories of interest:

* <https://gitlab.com/gitlab-com/gl-infra/k8s-workloads>

## Cluster Configurations

* Configurations for how our GKE clusters and associated node pools are defined
  are stored in <https://ops.gitlab.net/gitlab-com/gl-infra/config-mgmt/>
* For our staging and production environments, we run 1 regional cluster, and 3
  zonal clusters
* The 3 zonal clusters are clusters that are locked into the zone for which
  Google provides for the chosen region we are operating out of
* These cluster splits allow us to perform some cost savings and limiting blast
  radius in the case of cluster failures

### Naming Conventions

We're leveraging a similar setup to how GKE names clusters.  The overall template looks like this: `<provider>_<project>_<location>_<cluster_name>`.  Where:

* `provider` refers to the Cloud Provider hosting our cluster
* `project` refers to the logical location or account where the cluster can be found
* `location` the physical location of said cloud provider where the cluster exists; we make no special declaration as to whether the cluster is a regional or zonal cluster, it is assumed the user will either leverage the labels/tags applied to the cluster, or careful inspection of the name here to provide the differnetiation
* `cluster_name` is the name/id of the cluster as its defined in the provider, it should follow the format `<purpose>-<uid>`:
  * `purpose` is a loosely defined mechanism to help deliniate the intention for the cluster
  * `uid` is a unique identifier as it may be common to spin up multiple clusters with the same purpose in the same location

Examples:

* `gke_gitlab-staging-1_us-east1_gitlab-7vrx8` - where:
  * `provider` - is GKE
  * `project` - `gitlab-staging-1`
  * `location` - this is a regional cluster that resides in `us-east1`
  * `cluster_name` - hosting of `gitlab` related services with UID`7vrx8`
* `gke_gitlab-production_us-east1-b_gitlab-rw5e2` - where:
  * `provider` - is GKE
  * `project` - `gitlab-production`
  * `location` - this is a zonal cluster located in `us-east1-b`
  * `cluster_name` - hosting of `gitlab` related services with UID`rw5e2`

This is an enhancement that was enacted 2023-06-14.  Thus our older naming convention may remain in some areas.

### DNS Naming Schema

We'll leverage the above name but reverse it for the purposes of DNS.  This enables us to more logically follow DNS standards and prevent ourselves from running into limitations.  The above examples translated:

* `gke_gitlab-staging-1_us-east1_gitlab-7vrx8` - `gitlab-7vrx8.us-east1.gitlab-staging-1.gke.gitlab.net`
* `gke_gitlab-production_us-east1-b_gitlab-rw5e2` - `gitlab-rw5e2.us-east1-b.gitlab-production.gke.gitlab.net`

### Typical Deployments

* Anything related to observability are installed on all clusters
* Sidekiq, PlantUML, Kubernetes Agent Service are installed onto the Regional
  Clusters
* API, Git, Registry, and Websocket deployments are configured on the zonal
  clusters to which HAProxy is then configured to reach to each zone as desired

## Kubernetes Log Hunting

Our logging mechanism for GKE will capture all events coming from the Kubernetes
Cluster, but may not capture events for the nodes themselves.  We'll receive
logs from services running on the nodes, but not operations done by Google.
Keep this in mind if you are ever working with preemtible instances, that some
data may just stop showing up.

### Preemptible Searching

Preemptible instances are cycled roughly every 24 hours.  Since those nodes will
disappear from Google, we'll sometimes see entries from nonexisting nodes in
Kibana.  You can find in Stackdriver when a node was cycled using this example
filter: [`jsonPayload.event_subtype="compute.instances.preempted"`](https://console.cloud.google.com/logs/viewer?project=gitlab-pre&minLogLevel=0&expandAll=false&customFacets&limitCustomFacetWidth=true&dateRangeStart=2019-07-21T18%3A37%3A45.912Z&dateRangeEnd=2019-07-22T18%3A37%3A45.912Z&interval=P1D&resource=gce_instance%2Finstance_id%2F8024017080378216245&advancedFilter=jsonPayload.event_subtype%3D%22compute.instances.preempted%22%0A%0A&scrollTimestamp=2019-07-22T16%3A56%3A40.046986000Z)

Ensure to change to the correct project and adjust the times to search as
necessary.

### Kibana

#### Events log for a namespace

Events log stores data from objects similar to doing a `kubectl describe
<object> <objectID>`

This can be found in Kibana on object `json.logName`.  This will be set to
`proejcts/<PROJECT_NAME>/logs/events`.  Example:
`json.logName="projects/gitlab-pre/logs/events"`

This will provide all event data for that Cluster, generated by various
Kubernetes Objects.  We can then proceed to filter based on the data we are
looking for.

* Look for events related to things happening in a specific namespace:
  `json.jsonPayload.involvedObject.namespace` - simply provide it the name of
  the namespace we are looking for
* Look for events related to a specific _type_ of object:
  `json.jsonPayload.involvedObject.kind` - provide it the name of the object,
  example `Service`, `DaemonSet`, `Pod`, etc...
* Look for events targeting a specifc Pod:
  `json.jsonPayload.involvedObject.name` - bonus points when you use a wildcard
  here, you can find events related to all pods of a specific application and or
  replicaset. Examples to filter on:
  * Specific Pod: `gitlab-registry-68cbc8c489-nh9s9`
  * All pods of a replicaset: `gitlab-registry-68cbc8c489`
  * All pods of the deployment: `gitlab-registry`

With all of the above filters set, `json.jsonPayload.message` is going to have
the important bits of information.

#### Events from Pods

Pods emit logs from each container running inside of it, into it's own "log"
inside of stackdriver.  Which means we can search based on the name of the
container running inside of that Pod.  Using the following example:

* Filter `json.logName="projects/gitlab-pre/logs/registry"` - we'll see all log
  data generated by any container named registry.

You can use the same filters above to help sift through specific Pods and
namespaces as desired.

Log data is output in both `stderr` and `stdout`.  Utilize the filter
`json.labels.container.googleapis.com/stream` you can specify either if you
wish.

The desired event data for this style of search will exist in `json.textPayload`

# Alerts

## GitLabZonalCompomentVersionsOutOfSync

We want to ensure that we do not suffer drift for GitLab components across all
of our clusters for a lengthy period of time.  If this alert triggers this means
that there is a chance that at least 1 cluster may have at least 1 component out
of sync with the rest of the clusters.  Check the following items:

1. Verify there is no active maintenance occurring on any given cluster
1. Verify Auto-Deploy is not stuck or has failed recently
1. Begin troubleshooting by determining which cluster may be running an
   incorrect version of any GitLab component.  Utilize the chart provided on the
   alert as a starting point

## HPAScaleCapability

The Horizontal Pod Autoscaler has reached it's maximum configured allowed Pods.
This doesn't necessarily mean we are in trouble.

1. Start troubleshooting by validating the service is able to successfully handle
   requests. Utilize the SLI/SLO metrics of the service that is alerting to determine
   if we are violating any service Apdex or Errors
1. If we are not suffering problems, this means we need to further tweak the HPA
   and better optimize its configuration.  Open an issue, noting your findings.
1. Create an alert silence for a period of time and ensure the newly created
   issue is appropriately prioritized to be completed prior to the expiration of
   the silence.
1. If we are violating the service SLI/SLO's we must take further action.  Use
   guidelines below to assist in taking the appropriate action.

When we reach this threshold we must start an investigation into the load that
this service is taking to see if there's been a trend upward that we simply
haven't noticed over time, or if there's a problem processing requests which led
to an undesired effect of scaling upwards out of normal.

Utilize the dashboard
<https://dashboards.gitlab.net/d/alerts-sat_kube_horizontalpodautoscaler/alerts-kube_horizontalpodautoscaler_desired_replicas-saturation-detail>
and observe the Saturation over the course of time to take into account how many
Pods we've been scaling.  Normally we scale with traffic, but how this is
derived differs between services.  If we've been scaling up over a lengthy
period of time (say months), it may simply mean we need to bump the amount of
maximum allowed Pods only if we are in violation of other SLO's for said service.

During the investigation, take a look at the HPA configuration to understand
what drives the scaling needs.  This will help determine what signals to look
deeper into and drive the conversation for what changes need to be made.  When
making changes to the HPA we need to ensure that the cluster will not endure
undue stress.

These configurations are located:
<https://gitlab.com/gitlab-com/gl-infra/k8s-workloads/gitlab-com/>

## GKENodeCountCritical

We have reached the maximum configured amount of nodes allowed by all node pools.
We must make changes to the node pool configuration.  This is maintained in
Terraform here: [ops.gitlab.net/.../gitlab-com-infrastructure/.../gprd/main.tf](https://ops.gitlab.net/gitlab-com/gitlab-com-infrastructure/blob/e3f1f5edfe90d98f4e410bfc5cc79b265b5fa1f0/environments/gprd/main.tf#L1797)

## GKENodeCountHigh

We are close to reaching the maximum allowed nodes in the node_pool
configuration as defined by terraform.  It would be wise to open an issue an
investigate node resource contention and determine if we should consider raising
this limit or target a service which may be using more resources than considered
normal.

Observe our node pool counts to determine if a particular node pool is at it's
maximum.  If so, we need to investigate the workloads running on this node pool
to determine if we need to simply bump the maximum count for that node pool or
shift workloads around to a differing node pool

Trends for node scaling can be seen using this metric over the course of time:
`count(stackdriver_gce_instance_compute_googleapis_com_instance_uptime{instance_name=~"gke-gprd.*"})`

## `KubeContainersWaitingInError`

More than 50% of the containers waiting to start for a deployment are waiting due
to reasons that we consider to be an error state (that is, any reason other than
`ContainerCreating`).

Review the [Grafana Dashboard](https://dashboards.gitlab.net/d/alerts-kube_containers_waiting/alerts-containers-waiting),
for a detailed breakdown of the reasons why containers are not starting.

There are many reasons why containers will fail to start, but some include:

1. GCP Quota Limits: we are unable to increase the capacity of a node pool.
1. A configuration error has been pushed to the application, resulting in a termination during startup and a `CrashLoopBackOff`.
1. Kubernetes is unable to pull the required image from the registry
1. An increase in the amount of containers that need to be created during a deployment.
1. Calico-typha pods have undergone a recent migration/failure (see below)

### Calico Related Failures

To check if a calico related migration or failure is the cause, follow the steps:

```bash
1. kubectl get pods -n kube-system | grep calico-typha
    1. # Have any of the pods restarted recently around the time of the incident?
1. kubectl logs calico-typha-XXX-YYY -n kube-system
```
