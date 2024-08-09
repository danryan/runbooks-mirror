# GitalyServiceGoserverTrafficCessationSingleNode

**Table of Contents**

[TOC]

## Overview

- The `GitalyServiceGoserverTrafficCessationSingleNode` alert is a SLI that monitors Gitaly GRPC requests in aggregate, excluding the OperationService. GRPC failures which are considered to be the "server's fault" are counted as errors. The apdex score is based on a subset of GRPC methods which are expected to be fast.

This alert signifies that the SLI is reporting a cessation of traffic to the goserver component of the gitaly service on a single node; the signal is present, but is zero.
Since the service is not fully redundant, SLI violations on a single node may represent a user-impacting service degradation.

The following conditions must be met to trigger this alert:

- `gitlab_component_node_ops:rate_30m{component="goserver",env="[env]",monitor="global",type="gitaly"} == 0`
     Checks if the rate of operations for goserver in the gitaly service is zero over the past 30 minutes. This condition confirms that we are not currently seeing any traffic.

- `gitlab_component_node_ops:rate_30m{component="goserver",env="[env]",monitor="global",type="gitaly"} offset 1h >= 0.16666666666666666`
     Checks if the rate of operations for goserver in the gitaly service one hour ago was greater than or equal to approximately 0.167 (1/6) requests per second. This condition confirms that we saw some traffic an hour ago.

- A stuck process on a Gitaly node may cause this issue.
- The Gitaly node might not be able to serve traffic
- The recipient is required to figure out the [impact of the service outage](#severities), validate if the Gitaly node is at all serving [traffic](https://dashboards.gitlab.net/d/gitaly-main/gitaly3a-overview?orgId=1) , if the root cause seems to be linked to Gitaly it is suggested to [reach out to the Gitaly team](#escalation) so that they can help with the investigation.
- To figure out the impact it is important to note Gitaly does not replicate any data. If a Gitaly server goes down, any of its clients can't read or write to the repositories stored on that server.

## Services

- [Gitaly Service](https://gitlab.com/gitlab-org/gitaly/blob/master/README.md)
- Team that owns the service: [Core Platform : Gitaly](https://handbook.gitlab.com/handbook/engineering/infrastructure/core-platform/systems/gitaly/)
- **Label:** gitlab-com/gl-infra/production~"Service::Gitaly"

## Metrics

- The alert is based on the metric gitaly_service_client_requests_total, which tracks the total number of gRPC requests made to the Gitaly service. Specifically, it monitors the rate of these requests over a specified time window, excluding the OperationService.
The alert calculates the rate of requests over a 5-minute window to determine if there has been a cessation of traffic.
[Link to Metrics Catalog](https://gitlab.com/gitlab-com/runbooks/-/blob/master/mimir-rules/gitlab-gprd/gitaly/autogenerated-gitlab-gprd-gitaly-service-level-alerts.yml#L521)
- Checking the log file for new log entries (e.g. tail -f /var/opt/gitlab/gitaly/current), if there are then it's a false-positive alert.
- Dashboard when the alert is [firing](../img/GitalyServiceGoserverTrafficCessationSingleNode.png)

## Alert Behavior

- [To cross-check if a Gitaly Migration is in-progress](https://gitlab.com/gitlab-com/gl-infra/production/-/issues/?sort=created_date&state=opened&first_page_size=100) of Gitaly nodes may cause this alert, which might require us to [silence](https://alerts.gitlab.net/#/silences/new?filter={alertname%3D~%22GitalyServiceGoserverTrafficCessationSingleNode%7C%22%2Ctype%3D%22gitaly%22%2Cenv%3D%22gprd%22%2Cfqdn%3D%22%24STORAGE_NAME%22) this alert.
- Silencing will also be required if a Gitaly node got recently created
- This alert is expected to be rare
- Historical trends of the alert firing [here]("https://nonprod-log.gitlab.net/app/discover#/?_g=(filters:!(),refreshInterval:(pause:!t,value:0),time:(from:now-1y%2Fd,to:now))&_a=(columns:!(message,stage,type,source,username,alert_labels.alertname),filters:!(),index:b35d9ca0-6c67-11eb-968b-c18082d502f4,interval:auto,query:(language:kuery,query:'alert_labels.alertname.keyword%20:%20%22GitalyServiceGoserverTrafficCessationSingleNode%22'),sort:!(!(time,asc)))")

## Severities

- This alert might create S2 incidents.
- There might be some gitlab.com users impacted , to figure out the exact number of respositories that cannot be accessed a query like [this](https://dashboards.gitlab.net/explore?schemaVersion=1&panes=%7B%22f5o%22:%7B%22datasource%22:%22mimir-gitlab-gprd%22,%22queries%22:%5B%7B%22refId%22:%22A%22,%22expr%22:%22gitaly_total_repositories_count%7Bfqdn%3D%5C%22gitaly-01-stor-gprd.c.gitlab-gitaly-gprd-0fe1.internal%5C%22,prefix%3D%5C%22@hashed%5C%22%7D%22,%22range%22:true,%22instant%22:true,%22datasource%22:%7B%22type%22:%22prometheus%22,%22uid%22:%22mimir-gitlab-gprd%22%7D,%22editorMode%22:%22code%22,%22legendFormat%22:%22__auto%22%7D%5D,%22range%22:%7B%22from%22:%22now-1h%22,%22to%22:%22now%22%7D%7D%7D&orgId=1) would give you a good estimate.
- Review [Incident Severity Handbook](https://handbook.gitlab.com/handbook/engineering/infrastructure/incident-management/#incident-severity) page to identify the required Severity Level

## Verification

- Prometheus [link to query](https://dashboards.gitlab.net/explore?schemaVersion=1&panes=%7B%22f5o%22:%7B%22datasource%22:%22mimir-gitlab-gprd%22,%22queries%22:%5B%7B%22refId%22:%22A%22,%22expr%22:%22gitlab_component_node_ops:rate_30m%7Bcomponent%3D%5C%22goserver%5C%22,env%3D%5C%22gprd%5C%22,monitor%3D%5C%22global%5C%22,type%3D%5C%22gitaly%5C%22%7D%20%3D%3D%200%20and%20gitlab_component_node_ops:rate_30m%7Bcomponent%3D%5C%22goserver%5C%22,env%3D%5C%22gprd%5C%22,monitor%3D%5C%22global%5C%22,type%3D%5C%22gitaly%5C%22%7D%20offset%201h%20%3E%3D%200.16666666666666666%22,%22range%22:true,%22instant%22:true,%22datasource%22:%7B%22type%22:%22prometheus%22,%22uid%22:%22mimir-gitlab-gprd%22%7D,%22editorMode%22:%22code%22,%22legendFormat%22:%22__auto%22%7D%5D,%22range%22:%7B%22from%22:%221713438000000%22,%22to%22:%221713445199000%22%7D%7D%7D&orgId=1) that triggered the alert
- [Gitaly Service Overview dashboard](https://dashboards.gitlab.net/d/gitaly-main/gitaly3a-overview?orgId=1)
- [Mimir Gitaly instances status in gprd environment](https://dashboards.gitlab.net/explore?schemaVersion=1&panes=%7B%22yah%22:%7B%22datasource%22:%22e58c2f51-20f8-4f4b-ad48-2968782ca7d6%22,%22queries%22:%5B%7B%22refId%22:%22A%22,%22expr%22:%22up%7Bjob%3D%5C%22scrapeConfig%2Fmonitoring%2Fprometheus-agent-gitaly%5C%22,tier%3D%5C%22stor%5C%22,type%3D%5C%22gitaly%5C%22,env%3D%5C%22gprd%5C%22%7D%22,%22range%22:true,%22instant%22:true,%22datasource%22:%7B%22type%22:%22prometheus%22,%22uid%22:%22e58c2f51-20f8-4f4b-ad48-2968782ca7d6%22%7D,%22editorMode%22:%22code%22,%22legendFormat%22:%22__auto%22%7D%5D,%22range%22:%7B%22from%22:%22now-1h%22,%22to%22:%22now%22%7D%7D%7D&orgId=1)

## Recent changes

- [Recent Gitaly Production Change/Incident Issues](https://gitlab.com/gitlab-com/gl-infra/production/-/issues/?sort=created_date&state=all&label_name%5B%5D=Service%3A%3AGitaly&first_page_size=100)
- [Recent chef-repo Changes](https://gitlab.com/gitlab-com/gl-infra/chef-repo/-/merge_requests?scope=all&state=merged)
- [Recent k8s-workloads Changes](https://gitlab.com/gitlab-com/gl-infra/k8s-workloads/gitlab-com/-/merge_requests?scope=all&state=merged)

## Troubleshooting

- Checking the log file for new log entries (e.g. tail -f /var/opt/gitlab/gitaly/current), if there are then it's a false-positive alert.
- Checking if there are more than one Gitaly instance running (e.g. ps faux | grep "gitaly serve"). Multiple Gitaly instances could indicate that Prometheus is scraping metrics from an old process that's exiting and no longer serve requests, hence the alert.
- Is there a Gitaly server running, check the logs for mis-configuration or node-specific errors (bad permissions, insufficient memory or disk space, etc.)
- Has the node been removed from Rails config and thus no longer receiving traffic from Rails? This is a rare situation and it would be obvious from other alerts (usually 500s) as accessing repos would just fail.
- Has the node been recently created? If so then the creator forgot to add a silence.
- If the Gitaly nodes are unreachable for example in an incident like [this](https://gitlab.com/gitlab-com/gl-infra/production/-/issues/18165) a solution might be to increase the number of [ansible forks](https://gitlab.com/gitlab-com/gl-infra/production/-/issues/18165#note_1956592826)

## Possible Resolutions

- [Issue 17859](https://gitlab.com/gitlab-com/gl-infra/production/-/issues/17859)
- [Issue 18165](https://gitlab.com/gitlab-com/gl-infra/production/-/issues/18165)
- [Previous GitalyServiceGoserverTrafficCessationSingleNode incidents](https://gitlab.com/gitlab-com/gl-infra/production/-/issues/?sort=created_date&state=closed&label_name%5B%5D=Service%3A%3AGitaly&label_name%5B%5D=a%3AGitalyVersionMismatch&first_page_size=100)

## Dependencies

- Internal dependencies like migrations , a stuck process in Gitaly node , insufficient number of ansible forks may
cause this alert.

- External dependencies like regional outage may cause this alert.

# Escalation

- Please use /devoncall <incident_url> on Slack for any escalation that meets the [criteria](https://handbook.gitlab.com/handbook/engineering/development/processes/infra-dev-escalation/process/#scope-of-process).

- There would be soon a PagerDuty escalation policy for Gitaly incidents view [here](https://gitlab.com/groups/gitlab-org/core-platform-section/-/epics/4)

For escalation contact the following channels:

- [#g_gitaly](https://gitlab.enterprise.slack.com/archives/C3ER3TQBT)

Alternative slack channels:

- [#production_engineering](https://gitlab.enterprise.slack.com/archives/C03QC5KNW5N)
- [#infrastructure-lounge](https://gitlab.enterprise.slack.com/archives/CB3LSMEJV)

# Definitions

- [Link to edit this playbook](https://gitlab.com/gitlab-com/runbooks/-/tree/master/docs/gitaly/alerts/GitalyServiceGoserverTrafficCessationSingleNode.md?ref_type=heads)
- [Update the template used to format this playbook](https://gitlab.com/gitlab-com/runbooks/-/edit/master/docs/template-alert-playbook.md?ref_type=heads)

# Related Links

- [Related alerts](https://gitlab.com/gitlab-com/runbooks/-/blob/master/docs/gitaly/alerts/)
- [Gitaly Runbook docs](https://gitlab.com/gitlab-com/runbooks/-/blob/master/docs/gitaly)
- [Update the template used to format this playbook](https://gitlab.com/gitlab-com/runbooks/-/edit/master/docs/template-alert-playbook.md?ref_type=heads)