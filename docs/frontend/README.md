<!-- MARKER: do not edit this section directly. Edit services/service-catalog.yml then run scripts/generate-docs -->
[[_TOC_]]

#  Frontend Service
* [Service Overview](https://dashboards.gitlab.net/d/frontend-main/frontend-overview)
* **Alerts**: https://alerts.gitlab.net/#/alerts?filter=%7Btype%3D%22frontend%22%2C%20tier%3D%22lb%22%7D
* **Label**: gitlab-com/gl-infra/production~"Service:HAProxy"

## Logging

* [haproxy](https://console.cloud.google.com/logs/viewer?project=gitlab-production&organizationId=769164969568&interval=PT1H&resource=gce_instance%2Finstance_id%2F1812745190666049211&scrollTimestamp=2019-01-22T15:27:18.915253748Z&advancedFilter=resource.type%3D%22gce_instance%22%0Alabels.tag%3D%22haproxy%22)

## Troubleshooting Pointers

* [haproxy.md](haproxy.md)
* [../git/deploy-gitlab-rb-change.md](../git/deploy-gitlab-rb-change.md)
* [../git/gitlab-hosted-codesandbox.md](../git/gitlab-hosted-codesandbox.md)
* [../gitaly/gitaly-latency.md](../gitaly/gitaly-latency.md)
* [../gitaly/gitaly-permission-denied.md](../gitaly/gitaly-permission-denied.md)
* [../monitoring/sentry-is-down.md](../monitoring/sentry-is-down.md)
* [../registry/gitlab-registry.md](../registry/gitlab-registry.md)
* [../uncategorized/alert-for-ssl-certificate-expiration.md](../uncategorized/alert-for-ssl-certificate-expiration.md)
* [../uncategorized/chef-guidelines.md](../uncategorized/chef-guidelines.md)
* [../uncategorized/manage-workers.md](../uncategorized/manage-workers.md)
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
