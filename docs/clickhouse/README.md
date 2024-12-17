<!-- MARKER: do not edit this section directly. Edit services/service-catalog.yml then run scripts/generate-docs -->

**Table of Contents**

[[_TOC_]]

# ClickHouse Cloud Service

* **Alerts**: <https://alerts.gitlab.net/#/alerts?filter=%7Btype%3D%22clickhouse%22%2C%20tier%3D%22inf%22%7D>
* **Label**: gitlab-com/gl-infra/production~"Service::Service::ClickHouseCloud"

## Logging

* [ClickHouse Cloud monitoring](https://clickhouse.cloud/services)

## Troubleshooting Pointers

* [ClickHouse Cloud Failure Remediation, Backup & Restore Process](backup-restore.md)
* [ErrorTracking main troubleshooting document](../errortracking/overview.md)
* [../product_analytics/clickhouse-backup-restore.md](../product_analytics/clickhouse-backup-restore.md)
* [../product_analytics/ssl-troubleshooting.md](../product_analytics/ssl-troubleshooting.md)
* [Managing Sentry in Kubernetes](../sentry/sentry.md)
<!-- END_MARKER -->

## Summary

[ClickHouse Cloud](https://clickhouse.cloud) is a managed verion of [ClickHouse DB](https://github.com/ClickHouse/ClickHouse).  It is managed by [ClickHouse Inc.](https://clickhouse.com)

We are adding ClickHouse Cloud databases to the GitLab.com staging and production environments.

### Contact

Any questions please reach out to the team in Slack via `#f_clickhouse` or tag `@gitlab-org/maintainers/clickhouse`

### Provisioners

For a list of team members responsible for provisioning and deprovisioning ClickHouse Cloud DBs see [tech_stack.yml](https://gitlab.com/gitlab-com/www-gitlab-com/-/blob/master/data/tech_stack.yml)

### ClickHouse Cloud Console

The management console for ClickHouse Cloud can be accessed at:

[https://clickhouse.cloud/services](https://clickhouse.cloud/services)

Log in via Google SSO.

You will need to have access granted by a [ClickHouse Cloud admin](https://gitlab.com/gitlab-com/team-member-epics/access-requests/-/issues/23987) to access the management console.  An Access Request is a typical way of granting this permission. ([example](https://gitlab.com/gitlab-com/team-member-epics/access-requests/-/issues/23987))

### Network Interconnect

Sidekiq and the Web tier will connect via HTTP on port 8443 via a public IP/host.  Inbound connection can be allow listed via IPv4 ranges.  See [ClickHouse IP Access List Docs](https://clickhouse.com/docs/en/manage/security/ip-access-list) for details.

* [GitLab Development Docs:](https://docs.gitlab.com/ee/development/database/clickhouse/clickhouse_within_gitlab.html#writing-database-queries)
* [ClickHouse HTTPS interface docs:](https://clickhouse.com/docs/en/interfaces/http)
* ClickHouse Cloud is configured to accept HTTPS connections on port 8443.

### GitLab.com Staging Database

GitLab.com Staging Database has the following attributes:

Name: gitlab-com-staging
Console URL: [https://clickhouse.cloud/service/57fa3208-48a1-494b-9f44-ea895895a369](https://clickhouse.cloud/service/57fa3208-48a1-494b-9f44-ea895895a369)

### GitLab.com Production Database

GitLab.com Production Database has the following attributes:

Name: gitlab-com-production
Console URL: [https://clickhouse.cloud/service/ad02dd6a-1dde-4f8f-858d-37462fd06058](https://clickhouse.cloud/service/ad02dd6a-1dde-4f8f-858d-37462fd06058)

### ClickHouse Cloud Backup & Restore

Runbook for restoring a ClickHouse Cloud instance from a backup after failure of an instance. [[Link](clickhouse-cloud-backup-restore.md)]

<!-- ## Architecture -->

<!-- ## Performance -->

<!-- ## Scalability -->

<!-- ## Availability -->

<!-- ## Durability -->

<!-- ## Security/Compliance -->

## Monitoring/Alerting

Built in Monitoring Dashboards can be accessed via the [ClickHouse Cloud Console](https://clickhouse.cloud/services).

A dashboard for monitoring and alerting performance metrics has been configured in [Runbooks](https://gitlab.com/gitlab-com/runbooks/-/blob/master/dashboards/clickhouse/clickhouse_service.json), [clickhouse-cloud-services](https://dashboards.gitlab.net/d/clickhouse-clickhouse_service/clickhouse3a-clickhouse-cloud-services)

Alerting has been configured through Runbooks to alert into Slack channel `#f_clickhouse_infra_alerts`

<!-- ## Links to further Documentation -->
