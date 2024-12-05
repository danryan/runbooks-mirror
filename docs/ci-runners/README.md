<!-- MARKER: do not edit this section directly. Edit services/service-catalog.yml then run scripts/generate-docs -->

**Table of Contents**

[[_TOC_]]

# CI Runners Service

* [Service Overview](https://dashboards.gitlab.net/d/ci-runners-main/ci-runners-overview)
* **Alerts**: <https://alerts.gitlab.net/#/alerts?filter=%7Btype%3D%22ci-runners%22%2C%20tier%3D%22sv%22%7D>
* **Label**: gitlab-com/gl-infra/production~"Service::CI Runners"

## Logging

* [shared runners](https://log.gprd.gitlab.net/goto/b9aed2474a7ffe194a10d4445a02893a)

## Troubleshooting Pointers

* [ApdexSLOViolation](../alerts/ApdexSLOViolation.md)
* [ci-apdex-violating-slo.md](ci-apdex-violating-slo.md)
* [service-ci-runners.md](service-ci-runners.md)
* [Zonal and Regional Recovery Guide](../disaster-recovery/recovery.md)
* [Rails SQL Apdex alerts](../patroni/rails-sql-apdex-slow.md)
<!-- END_MARKER -->

# CI Runner Overview

We have several different kind of runners. Below is a brief overview of each.
They all have acronyms as well, which are indicated next to each name.

* [Logging](#logging)
* [Troubleshooting Pointers](#troubleshooting-pointers)
* [Configuration management for the Linux based Runners fleet](linux/README.md)
* [SSH access](#ssh)
* [Runner Shards](#runner-shards)
  * [Internal Runners](#internal-runners)
  * [External Runners](#external-runners)
* [Cost Factors](#cost-factors)
* [Network Info](#network-info)
* [Monitoring](#monitoring)
* [Production Change Lock (PCL)](#production-change-lock-pcl)

## SSH

To ssh into any VM under the `gitlab-ci-155816` GCP project which hosts the runner-manager VMs, add the following to your `.config/ssh` file:

```
# ci-runner manager VMs
Host *.gitlab-ci-155816.internal
        ProxyJump   lb-bastion.ci.gitlab.com
```

## Runner Shards

### Internal Runners

* Private shard
* gitlab-org shard
* macos-staging shard

### External Runners

See [Hosted runners for -com](https://docs.gitlab.com/ee/ci/runners/index.html#hosted-runners-for-gitlabcom).

## Runner Deployments

### blue-green-deployment

Each of the gitlab.com SaaS runners shards have two running clusters, consisting of a set of runner-manager VMs available at all time, we refer to them as blue and green. This is meant to speed up the release of [GitLab Runner](https://gitlab.com/gitlab-org/gitlab-runner) by shifting traffic
between two identical environments that are running different versions of the application. For further info please see the [blue-green README](./release-cycle/blue_green_deployment.md).

Currently the deployment supports the following architectures:

1. [Linux Architecture](./linux/README.md)
1. [Mac Architecture](./macos/README.md)

## Cost Factors

Each runner has an associated `cost factor` that determines how many minutes are deducted from the customers account
per minute used. For example, if a cost factor was 2.0, the customer would use 2 minutes for each minute a CI job
runs. Below is a table that details the cost factor for each runner type.

| Runner Type                                 | Public Project Factor | Private Project Factor |
| ------------------------------------------- | --------------------- | ---------------------- |
| shared-runners-manager (srm)                | 0.0                   | 1.0                    |
| gitlab-shared-runners-manager (gsrm)        | 0.0                   | 1.0                    |
| windows-runners-manager (wsrm)              | 0.0                   | 1.0                    |
| gitlab-docker-shared-runners-manager (gsrm) | 0.0                   | 1.0                    |

## Network Info

### Ephemeral runner VMs networking

For high capacity shards (like `shared`) we create dedicated projects for ephemeral VMs.

All these projects have the same networking structure:

| Network Name        | Subnet Name          | CIDR            | Purpose                       |
| ------------------- | -------------------- | --------------- | ----------------------------- |
| `ephemeral-runners` | `ephemeral-runners`  | **UNIQUE CIDR** | Runner manager machines       |
| `runners-gke`       | `runners-gke`        | `10.9.4.0/24`   | Primary; GKE nodes range      |
| `runners-gke`       | `runners-gke`        | `10.8.0.0/16`   | Secondary; GKE pods range     |
| `runners-gke`       | `runners-gke`        | `10.9.0.0/22`   | secondary; GKE services range |

Please read [GCP documentation about `VPC-native
clusters`](https://cloud.google.com/kubernetes-engine/docs/concepts/alias-ips) to understand how the different
ranges of the subnet are being used by GKE.

#### Network peering theory and issues

As peering automatically adds routes, it may introduce a conflict if the network "in the middle" have two different
subnetworks with overlapping CIDR peered. Let's consider few simple examples.

##### Peering conflicting networks directly

```mermaid
graph LR
  classDef subnetwork          color:#fff,fill:#555,stroke:#000,stroke-dasharray: 5 5;
  classDef subnetwork_conflict color:#fff,fill:#555,stroke:#a00,stroke-width:2px,stroke-dasharray: 5 5;
  classDef vpc                 color:#fff,fill:#555,stroke:#000,stroke-width:2px;

  subgraph Network A
    subnetwork_A_1("10.0.1.0/24"):::subnetwork -->|part of| network_A["Network A"]:::vpc
    subnetwork_A_2("10.0.0.0/24"):::subnetwork_conflict -->|part of| network_A
  end

  subgraph Network B
    subnetwork_B_2("10.0.0.0/24"):::subnetwork_conflict -->|part of| network_B["Network B"]:::vpc
    subnetwork_B_1("10.0.2.0/24"):::subnetwork -->|part of| network_B
  end

  network_B ===|peering| network_A

  subnetwork_A_2 -.-|direct conflict| subnetwork_B_2

  linkStyle 5 stroke:#a00,stroke-width:2px,stroke-dasharray: 5 5;
```

In this example we have two networks: `Network A` and `Network B`. Both have two subnetworks defined. One of the
subnetworks in each of the networks is unique (`10.0.1.0/24` in `Network A` and `10.0.2.0/24` in `Network B`).
Both networks contain also a second subnetwork, which have exactly the same CIDR: `10.0.0.0/24`.

When trying to peer these two networks directly, we will get a routing conflict, as it will be impossible to
define where to route traffic to `10.0.0.0/24`. When defining this in GCP (which requires peering definition
to be specified from both sides), first side of peering will be saved. It will be however not activated yet
and GCP will fail and reject to create the second side of the peering.

**Conclusion:** Networks peered directly can't have conflicting CIDRs.

##### Peering conflicting networks with one hop between them

```mermaid
graph LR
  classDef subnetwork          color:#fff,fill:#555,stroke:#000,stroke-dasharray: 5 5;
  classDef subnetwork_conflict color:#fff,fill:#555,stroke:#a00,stroke-width:2px,stroke-dasharray: 5 5;
  classDef vpc                 color:#fff,fill:#555,stroke:#000,stroke-width:2px;

  subgraph Network A
    subnetwork_A_1("10.0.1.0/24"):::subnetwork -->|part of| network_A["Network A"]:::vpc
    subnetwork_A_2("10.0.0.0/24"):::subnetwork_conflict -->|part of| network_A
  end

  subgraph Network B
    subnetwork_B_2("10.0.0.0/24"):::subnetwork_conflict -->|part of| network_B["Network B"]:::vpc
    subnetwork_B_1("10.0.2.0/24"):::subnetwork -->|part of| network_B
  end

  subgraph Network C
    subnetwork_C_1("10.0.3.0/24"):::subnetwork -->|part of| network_C["Network C"]:::vpc
  end

  network_B ===|peering| network_C
  network_C ===|peering| network_A

  subnetwork_A_2 -.-|conflict in Network C| subnetwork_B_2

  linkStyle 7 stroke:#a00,stroke-width:2px,stroke-dasharray: 5 5;
```

Here we extend the previous example with a new network: `Network C`. It has only one subnetwork with unique CIDR:
`10.0.3.0/24`. Instead of peering `Network A` and `Network B` directly, we try to peer them through `Network C`.

For `Network A` there is no problem - it knows only one `10.0.0.0/24` subnetwork - its own. The same goes for
`Network B`.

However, when we will try to connect them both to `Network C`, it will report a conflict as it gets routing to
`10.0.0.0/24` CIDR from two different peers. When trying to apply this in GCP, one peering will be created
successfully. The second one will fail just like in the case of peering conflicting networks directly.

**Conclusion:** Two networks peered through third common network also can't have conflicting CIDRs.

##### Peering conflicting networks with more than one hop between them

```mermaid
graph LR
  classDef subnetwork color:#fff,fill:#555,stroke:#000,stroke-dasharray: 5 5;
  classDef vpc        color:#fff,fill:#555,stroke:#000,stroke-width:2px;

  subgraph Network A
    subnetwork_A_1("10.0.1.0/24"):::subnetwork -->|part of| network_A["Network A"]:::vpc
    subnetwork_A_2("10.0.0.0/24"):::subnetwork -->|part of| network_A
  end

  subgraph Network B
    subnetwork_B_2("10.0.0.0/24"):::subnetwork -->|part of| network_B["Network B"]:::vpc
    subnetwork_B_1("10.0.2.0/24"):::subnetwork -->|part of| network_B
  end

  subgraph Network C
    subnetwork_C_1("10.0.3.0/24"):::subnetwork -->|part of| network_C["Network C"]:::vpc
  end

  subgraph Network D
    subnetwork_D_1("10.0.4.0/24"):::subnetwork -->|part of| network_D["Network D"]:::vpc
  end

  network_B ===|peering| network_D
  network_C ===|peering| network_A
  network_D ===|peering| network_C
```

In this example we add fourth network: `Network D`. It has only one subnetwork with unique CIDR: `10.0.4.0/24`.
We also extend the peering chain, injecting `Network D` in the middle.

With this layout, we finally have no conflicts. `Network A` connected with `Network C` doesn't have any directly
overlapping subnetworks. As `Network C` is connected now with `Network D` it doesn't create conflict for `Network C`
as it was in the previous example.

Then we have `Network D`, which is connected with `Network B` and again without any direct overlapping.

The two only subnetworks that have conflicting CIDRs are now separated with two hops between them. As automatic
routing is being added only for directly connected networks, we have no place where two different routes for
`10.0.0.0/24` would show up.

**Conclusion:** If you need to define conflicting CIDRs, ensure that you have at least two hops when peering the VPC
networks. **Or in other words**: If you have more than two hops when peering VPC networks, you don't need to worry
about CIDR conflicts between the edge networks.

#### Networking layout design

Let's consider this example layout:

```mermaid
graph LR
  classDef subnetwork color:#fff,fill:#555,stroke:#000,stroke-dasharray: 5 5;
  classDef vpc        color:#fff,fill:#555,stroke:#000,stroke-width:2px;

  subgraph gitlab-ci
    ci_ci[gitlab-ci/ci]:::vpc
    ci_ci_bastion(bastion subnetwork):::subnetwork
    ci_ci_runner_managers(runner-managers subnetwork):::subnetwork
    ci_ci_ep(ephemeral-runners-private subnetwork):::subnetwork
    ci_ci_esgo(ephemeral-runners-shared-gitlab-org subnetwork):::subnetwork

    ci_ci_gke[gitlab-ci/gke]:::vpc
    ci_ci_gke_gke(gke subnetwork):::subnetwork

    ci_ci_bastion --> ci_ci
    ci_ci_runner_managers --> ci_ci
    ci_ci_ep --> ci_ci
    ci_ci_esgo --> ci_ci
    ci_ci ===|peering| ci_ci_gke
    ci_ci_gke_gke --> ci_ci_gke
  end

  subgraph gitlab-production
    prd_gprd[gitlab-production/gprd]:::vpc
    prd_gprd_monitoring(monitoring-gprd subnetwork):::subnetwork

    prd_gprd_monitoring --> prd_gprd
  end

  subgraph gitlab-ci-plan-free-4
    ci_plan_free_4_ephemeral[gitlab-ci-plan-free-4/ephemeral-runners]:::vpc
    ci_plan_free_4_ephemeral_e(ephemeral-runners subnetwork):::subnetwork

    ci_plan_free_4_gke[gitlab-ci-plan-free-4/gke]:::vpc
    ci_plan_free_4_gke_gke(gke subnetwork):::subnetwork

    ci_plan_free_4_ephemeral_e --> ci_plan_free_4_ephemeral
    ci_plan_free_4_ephemeral ===|peering| ci_plan_free_4_gke
    ci_plan_free_4_gke_gke --> ci_plan_free_4_gke
  end

  subgraph gitlab-ci-plan-free-3
    ci_plan_free_3_ephemeral[gitlab-ci-plan-free-3/ephemeral-runners]:::vpc
    ci_plan_free_3_ephemeral_e(ephemeral-runners subnetwork):::subnetwork

    ci_plan_free_3_gke[gitlab-ci-plan-free-3/gke]:::vpc
    ci_plan_free_3_gke_gke(gke subnetwork):::subnetwork

    ci_plan_free_3_ephemeral_e --> ci_plan_free_3_ephemeral
    ci_plan_free_3_ephemeral ===|peering| ci_plan_free_3_gke
    ci_plan_free_3_gke_gke --> ci_plan_free_3_gke
  end

  ci_ci ===|temporary peering| prd_gprd
  ci_ci ===|peering| ci_plan_free_3_ephemeral
  ci_ci ===|peering| ci_plan_free_4_ephemeral

  linkStyle 13 stroke:#0a0,stroke-width:4px;
```

`gitlab-ci-plan-free-3` project have two networks that are peered: `ephemeral-runners` and `gke`. They are peered as
Prometheus in `gke` network needs to be able to scrape node exporter on ephemeral VMs in `ephemeral-runners` network.

As it's a [direct peering](#peering-conflicting-networks-directly), the networks can't have conflicting CIDRS.

The same goes for `gitlab-ci-plan-free-4` project.

The `ephemeral-runners` networks from `gitlab-ci-plan-free-3` and `gitlab-ci-plan-free-4` are also peered with
`ci` network in `gitlab-ci` project. This is done because runner managers in `runner-managers` subnetwork
need to be able to communicate with ephemeral VMs created in the `gitlab-ci-plan-free-X` projects.

Here we have a mix of direct peering and [peering with one hop](#peering-conflicting-networks-with-one-hop-between-them):

* `gitlab-ci/ci` and `gitlab-ci-plan-free-3/ephemeral-runners` are peered directly, so their subnetworks
  can't have conflicting CIDRs.
* `gitlab-ci/ci` and `gitlab-ci-plan-free-3/gke` are peered through `gitlab-ci-plan-free-3/ephemeral-runners`. Their
  networks also can't have conflicting CIDRs, as this would create conflict in `gitlab-ci-plan-free-3/ephemeral-runners`.

Also `gitlab-ci-plan-free-X/ephemeral-runners` are connected between each other with only one hop (`gitlab-ci/ci`),
which means that all `ephemeral-runners` subnetwork need to have unique CIDRs.

`gitlab-ci-plan-free-X/gke` are connected with more than one hop (sibling `ephemeral-runners` network -> `gitlab-ci/ci`
network -> other `ephemeral-runners` network -> other `gitlab-ci-plan-free-X/gke` network), they may have exactly the
same CIDRs.

Having the peering rules in minds we've designed such networking layout:

1. Each project used for CI runners will have a dedicated `gke` network with `gke` subnetwork. As these are
   never connected directly or with one hop, they all will use exactly the same CIDR, following the philosophy of
   "convention over configuration".

1. The `ephemeral-runners` subnetworks will be conflicting, as they all will have a one-hop common point
   in `gitlab-ci/ci`. This means that we need to make them unique across whole layout. For that we will maintain
   [a list of unique CIDRs for `ephemeral-runners` subnetworks](#ephemeral-runners-unique-cidrs-list). The rule needs
   to be followed no matter if the network is created in a dedicated project (like the `ci-plan-free-X` ones) or
   in the main `gitlab-ci` project.

1. Utility subnetworks like `bastion` or `runner-managers` need to not conflict with any other subnetworks.
   As we will have just these two subnetworks only in `gitlab-ci/ci` network,
   [we've chosen static CIDRs](#gitlab-ci-project) for them and will not change that.

1. Until we will [introduce dedicated Prometheus servers](https://gitlab.com/gitlab-com/gl-infra/reliability/-/issues/13886)
   for our CI projects and integrate them with our Thanos cluster, we need to use our main Prometheus server in
   `gitlab-production` project. For that we've created and need to maintain a temporary peering between `gitlab-ci/ci`
   and `gitlab-production/gprd` networks. When creating this peering we've resolved all CIDR conflicts, so all is good
   for now and our `ephemeral-runners` CIDR creation rule should ensure we will not introduce new conflicts. We will
   however need to carefully chose the CIDR for the `gke` subnetworks, as there is one-hop peering between
   `gitlab-production/gprd` and `gitlab-ci/gke`.

#### `ephemeral-runners` unique CIDRs list

For `ephemeral-runners` subnetworks we've decided to use subsequent CIDRs, starting from `10.10.0.0/21`.

The `/21` network gives use place for 2046 nodes per network. In case we need more, we should consider
creating specific GCP projects for part of the ephemeral runners for such shard. This is what we did for `shared`
(which uses the `gitlab-ci-plan-free-X` projects).

Every new CIDR should start at directly after the previously reserved one ends.

**The list bellow is the SSOT of the CIDRs we should use!**

**Please consult every new range with it and keep this list up-to-date!**

**When adding any new ephemeral-runners subnetwork don't forget to update the
[`ci-gateway` firewall](#ci-gateway-ilb-firewall)!**

| Environment                                | Network `{$PROJECT}/$VPC/$SUBNETWORK`       | CIDR             |
|--------------------------------------------|---------------------------------------------|------------------|
| `GCP/gitlab-ci-plan-free-7`                | `ephemeral-runners/ephemeral-runners`       | `10.10.0.0/21`   |
| `GCP/gitlab-ci-plan-free-6`                | `ephemeral-runners/ephemeral-runners`       | `10.10.8.0/21`   |
| `GCP/gitlab-ci-plan-free-5`                | `ephemeral-runners/ephemeral-runners`       | `10.10.16.0/21`  |
| `GCP/gitlab-ci-plan-free-4`                | `ephemeral-runners/ephemeral-runners`       | `10.10.24.0/21`  |
| `GCP/gitlab-ci-plan-free-3`                | `ephemeral-runners/ephemeral-runners`       | `10.10.32.0/21`  |
| `GCP/gitlab-ci`                            | `ci/ephemeral-runners-private`              | `10.10.40.0/21`  |
| `GCP/gl-r-saas-l-m-amd64-gpu-1`            | `gitlab-ci/saas-l-m-gpu-s/p1`               | `10.10.48.0/21`  |
| `GCP/gitlab-ci`                            | `ci/ephemeral-runners-private-2`            | `10.10.56.0/21`  |
| `GCP/gitlab-ci-private-1`                  | `ephemeral-runners/ephemeral-runners`       | `10.10.64.0/21`  |
| `GCP/gitlab-ci-private-2`                  | `ephemeral-runners/ephemeral-runners`       | `10.10.72.0/21`  |
| `GCP/gitlab-ci-private-3`                  | `ephemeral-runners/ephemeral-runners`       | `10.10.80.0/21`  |
| `GCP/gitlab-ci-private-4`                  | `ephemeral-runners/ephemeral-runners`       | `10.10.88.0/21`  |
| `GCP/gitlab-r-saas-l-m-amd64-gpu-1`        | `ephemeral-runners/ephemeral-runners`       | `10.10.96.0/21`  |
| `GCP/gitlab-r-saas-l-m-amd64-gpu-2`        | `ephemeral-runners/ephemeral-runners`       | `10.10.104.0/21` |
| `GCP/gitlab-r-saas-l-m-amd64-gpu-3`        | `ephemeral-runners/ephemeral-runners`       | `10.10.112.0/21` |
| `GCP/gitlab-r-saas-l-m-amd64-1`            | `ephemeral-runners/ephemeral-runners`       | `10.10.120.0/21` |
| `GCP/gitlab-r-saas-l-m-amd64-2`            | `ephemeral-runners/ephemeral-runners`       | `10.10.128.0/21` |
| `GCP/gitlab-r-saas-l-m-amd64-3`            | `ephemeral-runners/ephemeral-runners`       | `10.10.136.0/21` |
| `GCP/gitlab-r-saas-l-m-amd64-4`            | `ephemeral-runners/ephemeral-runners`       | `10.10.144.0/21` |
| `GCP/gitlab-r-saas-l-m-amd64-5`            | `ephemeral-runners/ephemeral-runners`       | `10.10.152.0/21` |
| `GCP/gitlab-r-saas-l-l-amd64-1`            | `ephemeral-runners/ephemeral-runners`       | `10.10.160.0/21` |
| `GCP/gitlab-r-saas-l-l-amd64-2`            | `ephemeral-runners/ephemeral-runners`       | `10.10.168.0/21` |
| `GCP/gitlab-r-saas-l-l-amd64-3`            | `ephemeral-runners/ephemeral-runners`       | `10.10.176.0/21` |
| `GCP/gitlab-r-saas-l-l-amd64-4`            | `ephemeral-runners/ephemeral-runners`       | `10.10.184.0/21` |
| `GCP/gitlab-r-saas-l-l-amd64-5`            | `ephemeral-runners/ephemeral-runners`       | `10.10.192.0/21` |
| `GCP/gitlab-r-saas-l-s-amd64-1`            | `ephemeral-runners/ephemeral-runners`       | `10.10.200.0/21` |
| `GCP/gitlab-r-saas-l-s-amd64-2`            | `ephemeral-runners/ephemeral-runners`       | `10.10.208.0/21` |
| `GCP/gitlab-r-saas-l-s-amd64-3`            | `ephemeral-runners/ephemeral-runners`       | `10.10.216.0/21` |
| `GCP/gitlab-r-saas-l-s-amd64-4`            | `ephemeral-runners/ephemeral-runners`       | `10.10.224.0/21` |
| `GCP/gitlab-r-saas-l-s-amd64-5`            | `ephemeral-runners/ephemeral-runners`       | `10.10.232.0/21` |
| `GCP/gitlab-r-saas-l-s-amd64-6`            | `ephemeral-runners/ephemeral-runners`       | `10.10.240.0/21` |
| `GCP/gl-r-saas-l-m-amd64-gpu-2`            | `gitlab-ci/saas-l-m-gpu-s/p2`               | `10.10.248.0/21` |
| `GCP/gl-r-saas-l-m-amd64-gpu-3`            | `gitlab-ci/saas-l-m-gpu-s/p3`               | `10.11.8.0/21`   |
| `GCP/gitlab-r-saas-l-m-amd64-gitlab-org-5` | `ephemeral-runners/ephemeral-runners`       | `10.11.16.0/21`  |
| `GCP/gitlab-r-saas-l-m-amd64-gitlab-org-6` | `ephemeral-runners/ephemeral-runners`       | `10.11.24.0/21`  |
| `GCP/gitlab-r-saas-l-m-amd64-gitlab-org-1` | `ephemeral-runners/ephemeral-runners`       | `10.11.32.0/21`  |
| `GCP/gitlab-r-saas-l-m-amd64-gitlab-org-2` | `ephemeral-runners/ephemeral-runners`       | `10.11.40.0/21`  |
| `GCP/gitlab-r-saas-l-m-amd64-gitlab-org-3` | `ephemeral-runners/ephemeral-runners`       | `10.11.48.0/21`  |
| `GCP/gitlab-r-saas-l-m-amd64-gitlab-org-4` | `ephemeral-runners/ephemeral-runners`       | `10.11.56.0/21`  |
| `GCP/gitlab-ci-private-5`                  | `ephemeral-runners/ephemeral-runners`       | `10.11.64.0/21`  |
| `GCP/gitlab-ci-private-6`                  | `ephemeral-runners/ephemeral-runners`       | `10.11.72.0/21`  |
| `GCP/gitlab-r-saas-l-xl-amd64-1`           | `ephemeral-runners/ephemeral-runners`       | `10.11.104.0/21` |
| `GCP/gitlab-r-saas-l-xl-amd64-2`           | `ephemeral-runners/ephemeral-runners`       | `10.11.112.0/21` |
| `GCP/gitlab-r-saas-l-xl-amd64-3`           | `ephemeral-runners/ephemeral-runners`       | `10.11.120.0/21` |
| `GCP/gitlab-r-saas-l-xl-amd64-4`           | `ephemeral-runners/ephemeral-runners`       | `10.11.128.0/21` |
| `GCP/gitlab-r-saas-l-xl-amd64-5`           | `ephemeral-runners/ephemeral-runners`       | `10.11.136.0/21` |
| `GCP/gitlab-r-saas-l-2xl-amd64-1`          | `ephemeral-runners/ephemeral-runners`       | `10.11.144.0/21` |
| `GCP/gitlab-r-saas-l-2xl-amd64-2`          | `ephemeral-runners/ephemeral-runners`       | `10.11.152.0/21` |
| `GCP/gitlab-r-saas-l-2xl-amd64-3`          | `ephemeral-runners/ephemeral-runners`       | `10.11.160.0/21` |
| `GCP/gitlab-r-saas-l-2xl-amd64-4`          | `ephemeral-runners/ephemeral-runners`       | `10.11.168.0/21` |
| `GCP/gitlab-r-saas-l-2xl-amd64-5`          | `ephemeral-runners/ephemeral-runners`       | `10.11.176.0/21` |
| `GCP/gitlab-r-saas-l-m-arm64-1`            | `ephemeral-runners/ephemeral-runners`       | `10.11.184.0/21` |
| `GCP/gitlab-r-saas-l-m-arm64-2`            | `ephemeral-runners/ephemeral-runners`       | `10.11.192.0/21` |
| `GCP/gitlab-r-saas-l-m-arm64-3`            | `ephemeral-runners/ephemeral-runners`       | `10.11.200.0/21` |
| `GCP/gitlab-r-saas-l-l-arm64-1`            | `ephemeral-runners/ephemeral-runners`       | `10.11.208.0/21` |
| `GCP/gitlab-r-saas-l-l-arm64-2`            | `ephemeral-runners/ephemeral-runners`       | `10.11.216.0/21` |
| `GCP/gitlab-r-saas-l-l-arm64-3`            | `ephemeral-runners/ephemeral-runners`       | `10.11.224.0/21` |
| `GCP/gitlab-r-saas-l-s-arm64-1`            | `gitlab-ci/saas-l-s-arm64/p1`               | `10.12.48.0/21`  |
| `GCP/gitlab-r-saas-l-s-arm64-2`            | `gitlab-ci/saas-l-s-arm64/p2`               | `10.12.56.0/21`  |
| `GCP/gitlab-r-saas-l-s-arm64-3`            | `gitlab-ci/saas-l-s-arm64/p3`               | `10.12.64.0/21`  |
| `GCP/gitlab-r-saas-l-m-arm64-1`            | `ephemeral-runners/tmp-ephemeral-runners`   | `10.11.232.0/21` |
| `GCP/gitlab-r-saas-l-m-arm64-2`            | `ephemeral-runners/tmp-ephemeral-runners`   | `10.11.240.0/21` |
| `GCP/gitlab-r-saas-l-m-arm64-3`            | `ephemeral-runners/tmp-ephemeral-runners`   | `10.11.248.0/21` |
| `GCP/gitlab-r-saas-l-l-arm64-1`            | `ephemeral-runners/tmp-ephemeral-runners`   | `10.12.8.0/21`   |
| `GCP/gitlab-r-saas-l-l-arm64-2`            | `ephemeral-runners/tmp-ephemeral-runners`   | `10.12.16.0/21`  |
| `GCP/gitlab-r-saas-l-l-arm64-3`            | `ephemeral-runners/tmp-ephemeral-runners`   | `10.12.24.0/21`  |
| `GCP/gitlab-r-saas-l-s-arm64-1`            | `ephemeral-runners/tmp-ephemeral-runners`   | `10.12.72.0/21`  |
| `GCP/gitlab-r-saas-l-s-arm64-2`            | `ephemeral-runners/tmp-ephemeral-runners`   | `10.12.80.0/21`  |
| `GCP/gitlab-r-saas-l-s-arm64-3`            | `ephemeral-runners/tmp-ephemeral-runners`   | `10.12.88.0/21`  |
| `GCP/gitlab-ci`                            | `gitlab-ci-private/private-services`        | `10.12.40.0/21`  |
| `GCP/gitlab-r-saas-l-p-amd64-1`            | `gitlab-ci/gitlab-ci-private/p1`            | `10.13.0.0/21`   |
| `GCP/gitlab-r-saas-l-p-amd64-2`            | `gitlab-ci/gitlab-ci-private/p2`            | `10.13.8.0/21`   |
| `GCP/gitlab-ci-private-1`                  | `gitlab-ci/gitlab-ci-private/p3`            | `10.13.16.0/21`  |
| `GCP/gitlab-ci-private-2`                  | `gitlab-ci/gitlab-ci-private/p4`            | `10.13.24.0/21`  |
| `GCP/gitlab-ci-private-3`                  | `gitlab-ci/gitlab-ci-private/p5`            | `10.13.32.0/21`  |
| `GCP/gitlab-ci-private-4`                  | `gitlab-ci/gitlab-ci-private/p6`            | `10.13.40.0/21`  |
| `GCP/gitlab-ci-private-5`                  | `gitlab-ci/gitlab-ci-private/p7`            | `10.13.48.0/21`  |
| `GCP/gitlab-ci-private-6`                  | `gitlab-ci/gitlab-ci-private/p8`            | `10.13.56.0/21`  |
| `GCP/r-saas-l-m-amd64-1`                   | `gitlab-ci/r-saas-l-m-amd64/p1`             | `10.13.64.0/21`  |
| `GCP/r-saas-l-m-amd64-2`                   | `gitlab-ci/r-saas-l-m-amd64/p2`             | `10.13.72.0/21`  |
| `GCP/r-saas-l-m-amd64-3`                   | `gitlab-ci/r-saas-l-m-amd64/p3`             | `10.13.80.0/21`  |
| `GCP/r-saas-l-m-amd64-4`                   | `gitlab-ci/r-saas-l-m-amd64/p4`             | `10.13.88.0/21`  |
| `GCP/r-saas-l-m-amd64-5`                   | `gitlab-ci/r-saas-l-m-amd64/p5`             | `10.13.96.0/21`  |
| `GCP/r-saas-l-l-amd64-1`                   | `gitlab-ci/r-saas-l-l-amd64/p1`             | `10.13.104.0/21` |
| `GCP/r-saas-l-l-amd64-2`                   | `gitlab-ci/r-saas-l-l-amd64/p2`             | `10.13.112.0/21` |
| `GCP/r-saas-l-l-amd64-3`                   | `gitlab-ci/r-saas-l-l-amd64/p3`             | `10.13.120.0/21` |
| `GCP/r-saas-l-l-amd64-4`                   | `gitlab-ci/r-saas-l-l-amd64/p4`             | `10.13.128.0/21` |
| `GCP/r-saas-l-l-amd64-5`                   | `gitlab-ci/r-saas-l-l-amd64/p5`             | `10.13.136.0/21` |
| `GCP/r-saas-l-xl-amd64-1`                  | `gitlab-ci/r-saas-l-xl-amd64/p1`            | `10.13.144.0/21` |
| `GCP/r-saas-l-xl-amd64-2`                  | `gitlab-ci/r-saas-l-xl-amd64/p2`            | `10.13.152.0/21` |
| `GCP/r-saas-l-xl-amd64-3`                  | `gitlab-ci/r-saas-l-xl-amd64/p3`            | `10.13.160.0/21` |
| `GCP/r-saas-l-xl-amd64-4`                  | `gitlab-ci/r-saas-l-xl-amd64/p4`            | `10.13.168.0/21` |
| `GCP/r-saas-l-xl-amd64-5`                  | `gitlab-ci/r-saas-l-xl-amd64/p5`            | `10.13.176.0/21` |
| `GCP/r-saas-l-2xl-amd64-1`                 | `gitlab-ci/r-saas-l-2xl-amd64/p1`           | `10.13.184.0/21` |
| `GCP/r-saas-l-2xl-amd64-2`                 | `gitlab-ci/r-saas-l-2xl-amd64/p2`           | `10.13.192.0/21` |
| `GCP/r-saas-l-2xl-amd64-3`                 | `gitlab-ci/r-saas-l-2xl-amd64/p3`           | `10.13.200.0/21` |
| `GCP/r-saas-l-2xl-amd64-4`                 | `gitlab-ci/r-saas-l-2xl-amd64/p4`           | `10.13.208.0/21` |
| `GCP/r-saas-l-2xl-amd64-5`                 | `gitlab-ci/r-saas-l-2xl-amd64/p5`           | `10.13.216.0/21` |
| `GCP/r-saas-l-m-arm64-1`                   | `gitlab-ci/r-saas-l-m-arm64/p1`             | `10.13.224.0/21` |
| `GCP/r-saas-l-m-arm64-2`                   | `gitlab-ci/r-saas-l-m-arm64/p2`             | `10.13.232.0/21` |
| `GCP/r-saas-l-m-arm64-3`                   | `gitlab-ci/r-saas-l-m-arm64/p3`             | `10.13.240.0/21` |
| `GCP/r-saas-l-l-arm64-1`                   | `gitlab-ci/r-saas-l-l-arm64/p1`             | `10.13.248.0/21` |
| `GCP/r-saas-l-l-arm64-2`                   | `gitlab-ci/r-saas-l-l-arm64/p2`             | `10.14.0.0/21`   |
| `GCP/r-saas-l-l-arm64-3`                   | `gitlab-ci/r-saas-l-l-arm64/p3`             | `10.14.8.0/21`   |
| `GCP/r-saas-l-m-amd64-org-1`               | `gitlab-ci/r-saas-l-m-amd64-org/p1`         | `10.14.16.0/21`  |
| `GCP/r-saas-l-m-amd64-org-2`               | `gitlab-ci/r-saas-l-m-amd64-org/p2`         | `10.14.24.0/21`  |
| `GCP/r-saas-l-m-amd64-org-3`               | `gitlab-ci/r-saas-l-m-amd64-org/p3`         | `10.14.32.0/21`  |
| `GCP/r-saas-l-m-amd64-org-4`               | `gitlab-ci/r-saas-l-m-amd64-org/p4`         | `10.14.40.0/21`  |
| `GCP/r-saas-l-m-amd64-org-5`               | `gitlab-ci/r-saas-l-m-amd64-org/p5`         | `10.14.48.0/21`  |
| `GCP/r-saas-l-m-amd64-org-6`               | `gitlab-ci/r-saas-l-m-amd64-org/p6`         | `10.14.56.0/21`  |
| `GCP/r-saas-l-s-amd64-1`                   | `gitlab-ci/r-saas-l-s-amd64/p1`             | `10.14.64.0/21`  |
| `GCP/r-saas-l-s-amd64-2`                   | `gitlab-ci/r-saas-l-s-amd64/p2`             | `10.14.72.0/21`  |
| `GCP/r-saas-l-s-amd64-3`                   | `gitlab-ci/r-saas-l-s-amd64/p3`             | `10.14.80.0/21`  |
| `GCP/r-saas-l-s-amd64-4`                   | `gitlab-ci/r-saas-l-s-amd64/p4`             | `10.14.88.0/21`  |
| `GCP/r-saas-l-s-amd64-5`                   | `gitlab-ci/r-saas-l-s-amd64/p5`             | `10.14.96.0/21`  |
| `AWS/r-saas-m-staging`                     | `jobs-vpc/saas-macos-staging-blue-1`        | `10.20.0.0/21`   |
| `AWS/r-saas-m-staging`                     | `jobs-vpc/saas-macos-staging-blue-2`        | `10.20.8.0/21`   |
| `AWS/r-saas-m-staging`                     | `jobs-vpc/saas-macos-staging-green-1`       | `10.20.16.0/21`  |
| `AWS/r-saas-m-staging`                     | `jobs-vpc/saas-macos-staging-green-2`       | `10.20.24.0/21`  |
| `AWS/r-saas-m-m1`                          | `jobs-vpc/saas-macos-m1-blue-1`             | `10.30.0.0/21`   |
| `AWS/r-saas-m-m1`                          | `jobs-vpc/saas-macos-m1-blue-2`             | `10.30.8.0/21`   |
| `AWS/r-saas-m-m1`                          | `jobs-vpc/saas-macos-m1-green-1`            | `10.30.16.0/21`  |
| `AWS/r-saas-m-m1`                          | `jobs-vpc/saas-macos-m1-green-2`            | `10.30.24.0/21`  |
| `AWS/r-saas-m-l-m2pro`                     | `jobs-vpc/saas-macos-l-m2pro-blue-1`        | `10.40.0.0/21`   |
| `AWS/r-saas-m-l-m2pro`                     | `jobs-vpc/saas-macos-l-m2pro-blue-2`        | `10.40.8.0/21`   |
| `AWS/r-saas-m-l-m2pro`                     | `jobs-vpc/saas-macos-l-m2pro-green-1`       | `10.40.16.0/21`  |
| `AWS/r-saas-m-l-m2pro`                     | `jobs-vpc/saas-macos-l-m2pro-green-2`       | `10.40.24.0/21`  |

##### `ci-gateway` ILB firewall

When updating the `ephemeral-runners` CIDRs please remember to update the firewall rules for
the `ci-gateway` ILBs.

The rules are managed with Terraform in GPRD and GSTG environments within the `google_compute_firewall` resource
named `ci-gateway-allow-runners`.

The GPRD (GitLab.com) definition can be found [here](https://ops.gitlab.net/gitlab-com/gl-infra/config-mgmt/-/blob/743cf13a31633a62f9e6e8b67abeee3d151792ed/environments/gprd/main.tf#L2960).

The GSTG (staging.gitlab.com) definition can be found [here](https://ops.gitlab.net/gitlab-com/gl-infra/config-mgmt/-/blob/743cf13a31633a62f9e6e8b67abeee3d151792ed/environments/gstg/main.tf#L2957)

When doing any changes related to ephemeral runners make sure to check which GitLab environments that runner
supports (for example our `private` runners support both GPRD and GSTG while `shared` only GPRD) and update
the firewall rules respectively.

### GCP projects

Here you can find details about networking in different projects used by CI Runners service.

#### gitlab-ci project

| Network Name   | Subnet Name                 | CIDR            | Purpose                                                |
| -------------- | --------------------------- | --------------- | ------------------------------------------------------ |
| `default`      | `default`                   | `10.142.0.0/20` | all non-runner machines (managers, prometheus, etc.). In `us-east1` - we don't use this subnetwork in any other region. |
| `ci`           | `sd-exporter-ci`            | `10.142.16.0/24`| Monitoring subnetwork                                  |
| `ci`           | `bastion-ci`                | `10.1.4.0/24`   | Bastion network                                        |
| `ci`           | `runner-managers`           | `10.1.5.0/24`   | Network for Runner Managers ([new ones](https://gitlab.com/groups/gitlab-com/gl-infra/-/epics/456))                 |
| `runners-gke`  | `runners-gke`               | `10.9.4.0/24`   | Primary; GKE nodes range      |
| `runners-gke`  | `runners-gke`               | `10.8.0.0/16`   | Secondary; GKE pods range     |
| `runners-gke`  | `runners-gke`               | `10.9.0.0/22`   | secondary; GKE services range |

The `default` network will be removed once we will move all of the runner managers to a new
infrastructure, which is being tracked [by this epic](https://gitlab.com/groups/gitlab-com/gl-infra/-/epics/456).

The `ci` network will be getting new subnetworks for `ephemeral-runners-X` while working on
[this epic](https://gitlab.com/groups/gitlab-com/gl-infra/-/epics/456).

The `runners-gke` network, at least for now, is in the expected state.

#### gitlab-ci-windows project

| Network Name   | Subnet Name          | CIDR          | Purpose                           |
| -------------- | -------------------- | ------------- | --------------------------------- |
| `windows-ci`   | `manager-subnet`     | `10.1.0.0/16` | Runner manager machines           |
| `windows-ci`   | `executor-subnet`    | `10.2.0.0/16` | Ephemeral runner machines         |
| `windows-ci`   | `runner-windows-ci`  | `10.3.0.0/24` | Runner network for ansible/packer |
| `windows-ci`   | `bastion-windows-ci` | `10.3.1.0/24` | bastion network                   |

Windows project will most probably get the `runners-gke` network and GKE based monitoring in the future. This
is however not yet scheduled.

### `ci-gateway` Internal Load Balancers

To reduce the amount of traffic that goes through the public Internet (which causes additional costs)
and to add a little performance improvements, Runner managers and Git are set to use internal
load balancers which routes the traffic through GCP internal networking.

For that we've created a special VPC named `ci-gateway`. Dedicated VPC was added to avoid
peering with the main VPC of GitLab backend - for security reasons and to reduce the number
of possible CIDRs collisions.

This configuration was first tested with `private` runners shard and `staging.gitlab.com`. And
next was replicated in GPRD - for `gitlab.com` and with the three Linux runners shards we have.

```mermaid
graph LR
  subgraph project::GSTG
    subgraph VPC::gstg::gstg
      gstg_haproxy_b(HaProxy us-east1-b)
      gstg_haproxy_c(HaProxy us-east1-c)
      gstg_haproxy_d(HaProxy us-east1-d)

      gstg_gitlab_backends(GitLab backend services)

      gstg_haproxy_b -->|routes direct without peering| gstg_gitlab_backends
      gstg_haproxy_c -->|routes direct without peering| gstg_gitlab_backends
      gstg_haproxy_d -->|routes direct without peering| gstg_gitlab_backends
    end

    subgraph VPC::gstg::ci-gateway
      gstg_ci_gateway_ILB_b(ILB us-east1-b)
      gstg_ci_gateway_ILB_c(ILB us-east1-c)
      gstg_ci_gateway_ILB_d(ILB us-east1-d)
    end

    gstg_ci_gateway_ILB_b -->|routes direct without peering| gstg_haproxy_b
    gstg_ci_gateway_ILB_c -->|routes direct without peering| gstg_haproxy_c
    gstg_ci_gateway_ILB_d -->|routes direct without peering| gstg_haproxy_d
  end

  subgraph project::GPRD
    subgraph VPC::gprd::gprd
      gprd_haproxy_b(HaProxy us-east1-b)
      gprd_haproxy_c(HaProxy us-east1-c)
      gprd_haproxy_d(HaProxy us-east1-d)

      gprd_gitlab_backends(GitLab backend services)

      gprd_haproxy_b -->|routes direct without peering| gprd_gitlab_backends
      gprd_haproxy_c -->|routes direct without peering| gprd_gitlab_backends
      gprd_haproxy_d -->|routes direct without peering| gprd_gitlab_backends
    end

    subgraph VPC::gprd::ci-gateway
      gprd_ci_gateway_ILB_b(ILB us-east1-b)
      gprd_ci_gateway_ILB_c(ILB us-east1-c)
      gprd_ci_gateway_ILB_d(ILB us-east1-d)
    end

    gprd_ci_gateway_ILB_b -->|routes direct without peering| gprd_haproxy_b
    gprd_ci_gateway_ILB_c -->|routes direct without peering| gprd_haproxy_c
    gprd_ci_gateway_ILB_d -->|routes direct without peering| gprd_haproxy_d
  end

  subgraph project::gitlab-ci
    subgraph VPC::gitlab-ci::ci
      subgraph runner-managers
        runners_manager_private_1[runners-manager-private-1]
        runners_manager_private_2[runners-manager-private-2]

        runners_manager_shared_gitlab_org_X[runners-manager-shared-gitlab-org-X]

        runners_manager_shared_X[runners-manager-shared-X]
      end

      subgraph example-ephemeral-vms
        private_ephemeral_vm_1
        private_ephemeral_vm_2
        shared_gitlab_org_ephemeral_vm
      end

      runners_manager_private_1 -->|manages a job on| private_ephemeral_vm_1
      runners_manager_private_2 -->|manages a job on| private_ephemeral_vm_2

      runners_manager_shared_gitlab_org_X -->|manages a job on| shared_gitlab_org_ephemeral_vm
    end
  end

  subgraph project::gitlab-ci-plan-free-X
    subgraph VPC::gitlab-ci-plan-free-X::ephemeral-runners
      shared_ephemeral_vm
    end
  end

  runners_manager_shared_X --> shared_ephemeral_vm

  runners_manager_private_1 -->|connects through VPC peering| gstg_ci_gateway_ILB_c
  runners_manager_private_2 -->|connects through VPC peering| gstg_ci_gateway_ILB_d

  runners_manager_private_1 -->|connects through VPC peering| gprd_ci_gateway_ILB_c
  runners_manager_private_2 -->|connects through VPC peering| gprd_ci_gateway_ILB_d

  runners_manager_shared_gitlab_org_X -->|connects through VPC peering| gprd_ci_gateway_ILB_c

  runners_manager_shared_X -->|connects through VPC peering| gprd_ci_gateway_ILB_d

  private_ephemeral_vm_1 -->|connects through VPC peering| gstg_ci_gateway_ILB_c
  private_ephemeral_vm_2 -->|connects through VPC peering| gprd_ci_gateway_ILB_d

  shared_gitlab_org_ephemeral_vm -->|connects through VPC peering| gprd_ci_gateway_ILB_c

  shared_ephemeral_vm -->|connects through VPC peering| gprd_ci_gateway_ILB_d
```

#### How it's configured

The above diagram shows a general view of how this configuration is set up.

In both GSTG and GPRD projects we've created a dedicated VPC named `ci-gateway`. This VPC
contains Internal Load Balancers (ILBs) available on defined FQDNs. The VPCs are peered with
CI VPCs that contain runner managers and ephemeral VMs on which the jobs are executed.

As an ILB can route traffic only to nodes in the same VPC, we had to add a small change
to our HaProxy configuration. We've created a dedicated cluster of new HaProxy nodes
provisioned with two network interfaces: in `gprd` and in `ci-gateway` VPCs. The same
configuration is created in GSTG.

HaProxy got a new frontend named `https_git_ci_gateway` and listening on port `8989`. This
fronted passes the detected `git+https` traffic and a limited amount of API endpoints (purely
for Runner communication, which includes requesting for a job, sending trace update and sending
job update) to GitLab backends. Other requests are redirected with `307` HTTP response code
to `staging.gitlab.com` or `gitlab.com` - depending on the requested resource.

To reduce the cost that is created by traffic made across availability zones, in each project
we have two ILBs - one for each availability zone (`us-east1-c` and `us-east1-d`) used by the CI
fleet in the `us-east1` region. Each ILB is configured to target HaProxy nodes only in its
availability zone.

For that, the following FQDNs were created:

* `git-us-east1-c.ci-gateway.int.gstg.gitlab.net`
* `git-us-east1-d.ci-gateway.int.gstg.gitlab.net`
* `git-us-east1-c.ci-gateway.int.gprd.gitlab.net`
* `git-us-east1-d.ci-gateway.int.gprd.gitlab.net`

Runner nodes are configured to point the ILBs with the `url` and `clone_url` settings.
As we set our runners to operate in a specific availability zone, each of them
points the relevant ILB FQDN.

#### How it works

GitLab Runner is configured to talk with the dedicated ILB. Communication goes through
the VPC peering and reaches one of the HaProxy nodes backing the ILB. TLS certificate
is verified and Runner saves this information to configure Git in the job environment.

When job is received, Runner starts executing it on the ephemeral VM. It configures
Git to use the CAChain resolved from initial API request. Repo URL is configured to
use the ILB as GitLab's endpoint.

When job reaches the step in which sources are updated, `git clone` operation is
executed against the ILB. Communication again goes through the VPC peering and reaches
one of the HaProxy nodes. TLS certificate is verified using the CAChain resolved
earlier.

When job reaches the step when artifact needs to be downloaded or uploaded, it
also tries to talk with the ILB. However, HaProxy frontend detects that this
communication is unsupported and redirects it to the public Internet gateway
of GitLab instance that the job belongs to.

In the meantime, Runner receives job logs and transfers them back - together
with updating the status of the job - to GitLab's API. For that the communication
through VPC peering and the dedicaed ILB is used as well.

## Monitoring

![CI Runners monitoring stack design](./img/ci-runners-monitoring.png)

Monitoring is be defined in almost the same configuration in all CI related projects. It is deployed using GKE and
a cluster created by terraform. For that
[a dedicated terraform module](https://ops.gitlab.net/gitlab-com/gitlab-com-infrastructure/-/tree/master/modules/ci-runners/gke)
was created. For it's purpose the GKE cluster is using the `runners-gke` network defined above.

Prometheus is deployed in at least two replicas. Both have a Thanos Sidecar running alongside. Sidecar's gRPC
endpoint is exposed as publicly accessible (we don't want to peer the `ops` or `gprd` network here) and the GCP Firewall
limits access to it to only Thanos Query public IPs. This service uses TCP port `10901`.

Long-term metrics storage is handled by using a dedicated GCS bucket created by the terraform module alongside
the cluster. Thanos Sidecar is configured with write access to this bucket.

Apart from the Sidecar we also have Thanos Store Gateway and Thanos Compact deployed and configured to use the same
GCS bucket. Store Gateway's gRPC endpoint is exposed similarly to the Sidecar's one. This service uses TCP port `10903`.

[Traefik](https://traefik.io/) is used as the ingress and load-balancing mechanism. It exposes gRPC services on given
ports (using TCP routing), Prometheus UI and own dashboard. HTTP endpoints are automatically redirected to HTTPS,
and Let's Encrypt certificates are used for TLS.

For external access each project where monitoring is deployed is using a reserved public IP address. This address
is bound to two DNS A records:

* `monitoring-lb.[ENVIRONMENT].ci-runners.gitlab.net` - which is used for Thanos Query store DNS discovery and
  to access Traefik dashboard in the browser. Access to the Dashboard is limited by oAuth, using Google as the Identity
  Provider allowing `@gitlab.com` accounts. Consent screen and oAuth2 secrets are defined in the `gitlab-ci-155816`
  project and should be used for all deployments of this monitoring stack (**remember:** new deploys will use new
  domains for the redirection URLs, which should be added to the oAuth2 credentials configuration; unfortunately this
  can't be managed by terraform).
* `prometheus.[ENVIRONMENT].ci-runners.gitlab.net` - which is used to access directly the Prometheus deployment. As with
  the Traefik dashboard, access is limited by oAuth2 with the same configuration.

K8S deployment configuration is managed fully from CI. [A dedicated
project](https://gitlab.com/gitlab-com/gl-infra/ci-runners/k8s-workloads) covers all monitoring clusters in different
CI projects that we maintain.

## Production Change Lock (PCL)

It is a good practice to temporarily halt production changes during
certain events such as GitLab Summit, major global holidays, and
Weekends. Apart from the list already documented in
<https://about.gitlab.com/handbook/engineering/infrastructure/change-management/#production-change-lock-pcl>,
GitLab Runner extends this with the following:

| Dates                          | Type | Reason  |
| ------------------------------ | ---- | ------- |
| Recurring: Friday              | Soft | Friday  |
| Recurring: Weekend (Sat - Sun) | Soft | Weekend |

<!-- ## Summary -->

<!-- ## Architecture -->

<!-- ## Performance -->

<!-- ## Scalability -->

<!-- ## Availability -->

<!-- ## Durability -->

<!-- ## Security/Compliance -->

<!-- ## Monitoring/Alerting -->

<!-- ## Links to further Documentation -->
