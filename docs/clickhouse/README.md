<!-- MARKER: do not edit this section directly. Edit services/service-catalog.yml then run scripts/generate-docs -->

**Table of Contents**

[[_TOC_]]

# Clickhouse Service

* **Alerts**: <https://alerts.gitlab.net/#/alerts?filter=%7Btype%3D%22clickhouse%22%2C%20tier%3D%22inf%22%7D>
* **Label**: gitlab-com/gl-infra/production~"Service::Service::ClickHouseCloud"

## Logging

* [ClickHouse Cloud monitoring](https://clickhouse.cloud/services)

## Troubleshooting Pointers

* [ErrorTracking main troubleshooting document](../errortracking/overview.md)
<!-- END_MARKER -->

## Summary

[ClickHouse Cloud](https://clickhouse.cloud) is a managed verion of [ClickHouse DB](https://github.com/ClickHouse/ClickHouse).  It is managed by [ClickHouse Inc.](https://clickhouse.com)

We are adding ClickHouse Cloud databases to the GitLab.com staging and production environments.

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

Not yet provisioned

<!-- ## Architecture -->

<!-- ## Performance -->

<!-- ## Scalability -->

<!-- ## Availability -->

<!-- ## Durability -->

<!-- ## Security/Compliance -->

## Monitoring/Alerting

Built in Monitoring Dashboards can be accessed via the [ClickHouse Cloud Console](https://clickhouse.cloud/services).  We are investigating how to integrate these metrics into GitLab's grafana and alerting setup.

<!-- ## Links to further Documentation -->