<!-- MARKER: do not edit this section directly. Edit services/service-catalog.yml then run scripts/generate-docs -->

**Table of Contents**

[[_TOC_]]

# Container Registry Service

* [Service Overview](https://dashboards.gitlab.net/d/registry-main/registry-overview)
* **Alerts**: <https://alerts.gitlab.net/#/alerts?filter=%7Btype%3D%22registry%22%2C%20tier%3D%22sv%22%7D>
* **Label**: gitlab-com/gl-infra/production~"Service::Registry"

## Logging

* [Registry](https://log.gprd.gitlab.net/goto/9ec8a738ca23a17a9d7b61b4c3a9c96e)
* [haproxy](https://console.cloud.google.com/logs/viewer?project=gitlab-production&interval=PT1H&resource=gce_instance&customFacets=labels.%22compute.googleapis.com%2Fresource_name%22&advancedFilter=labels.tag%3D%22haproxy%22%0Alabels.%22compute.googleapis.com%2Fresource_name%22%3A%22fe-registry-%22)
* [Kubernetes](https://log.gprd.gitlab.net/goto/d614a5576099ff797be559c89fe88baa)

## Troubleshooting Pointers

* [TrafficAbsent and TrafficCessation](../alerts/TrafficAbsent.md)
* [Cloud SQL Troubleshooting](../cloud-sql/cloud-sql.md)
* [Cloudflare: Managing Traffic](../cloudflare/managing-traffic.md)
* [Interacting with Consul](../consul/interaction.md)
* [Measuring Recovery Activities](../disaster-recovery/recovery-measurements.md)
* [Zonal and Regional Recovery Guide](../disaster-recovery/recovery.md)
* [../duo/code_suggestion_failover.md](../duo/code_suggestion_failover.md)
* [Blocking individual IPs and Net Blocks on HA Proxy](../frontend/ban-netblocks-on-haproxy.md)
* [HAProxy Management at GitLab](../frontend/haproxy.md)
* [../gitlab-com-artifact-registry/overview.md](../gitlab-com-artifact-registry/overview.md)
* [CI Artifacts CDN](../google-cloud-storage/artifacts-cdn.md)
* [../kube/k8s-operations.md](../kube/k8s-operations.md)
* [Kubernetes](../kube/kubernetes.md)
* [Alerting](../monitoring/alerts_manual.md)
* [An impatient SRE's guide to deleting alerts](../monitoring/deleting-alerts.md)
* [Gitlab.com on Kubernetes](../onboarding/gitlab.com_on_k8s.md)
* [Diagnosis with Kibana](../onboarding/kibana-diagnosis.md)
* [Patroni Cluster Management](../patroni/patroni-management.md)
* [../patroni/postgresql-backups-wale-walg.md](../patroni/postgresql-backups-wale-walg.md)
* [Scaling Redis Cluster](../redis/scaling-redis-cluster.md)
* [Database Connection Pool Saturation](app-db-conn-pool-saturation.md)
* [Container Registry Batched Background Migrations](background-migrations.md)
* [Container Registry CDN](cdn.md)
* [Container Registry Database Index Bloat](db-index-bloat.md)
* [Container Registry Database Load Balancing](db-load-balancing.md)
* [Container Registry database post-deployment migrations](db-post-deployment-migrations.md)
* [gitlab-registry.md](gitlab-registry.md)
* [High Number of Overdue Online GC Tasks](online-gc-high-overdue-tasks.md)
* [High Number of Pending or Failed Outgoing Webhook Notifications](webhook-notifications.md)
* [Connecting To a Database via Teleport](../teleport/Connect_to_Database_Console_via_Teleport.md)
* [Deleting a project manually](../uncategorized/delete-projects-manually.md)
* [How to Use Vault for Secrets Management in Infrastructure](../vault/usage.md)
* [Vault Secrets Management](../vault/vault.md)
<!-- END_MARKER -->

<!-- ## Summary -->

<!-- ## Architecture -->

<!-- ## Performance -->

<!-- ## Scalability -->

<!-- ## Availability -->

<!-- ## Durability -->

<!-- ## Security/Compliance -->

<!-- ## Monitoring/Alerting -->

<!-- ## Links to further Documentation -->
