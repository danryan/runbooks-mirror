# ContainerRegistryNotificationsPendingCountTooHigh

**Table of Contents**

[TOC]

## Overview

- What does this alert mean?
  - The number of pending outgoing notifications is too high.
  - This can happen when notifications fail to be sent, typically seen if the following alerts happen:
    -  [ContainerRegistryNotificationsFailedStatusCode](./ContainerRegistryNotificationsFailedStatusCode.md)
    -  [ContainerRegistryNotificationsErrorCountTooHigh](./ContainerRegistryNotificationsErrorCountTooHigh.md)
- What factors can contribute?
  - Increased load on the registry pods.
  - Low available resources on the registry pods.
- What action is the recipient of this alert expected to take when it fires?
  - Network transient errors should self-heal.
  - [Troubleshooting](../webhook-notifications.md#troubleshooting).

## Services

- [Service Overview](../README.md)
- Team that owns the service: [Container Registry](hhttps://handbook.gitlab.com/handbook/engineering/development/ops/package/container-registry/)

## Metrics

- Metric: `registry_notifications_pending_total`.
> Briefly explain the metric this alert is based on and link to the metrics catalogue. What unit is it measured in? (e.g., CPU usage in percentage, request latency in milliseconds)
- [Dashboard URL](https://dashboards.gitlab.net/d/registry-notifications/registry-webhook-notifications-detail) focusing on the `Events queued per second` panel.
- The queue will grow while there are errors/failures.
> Explain the reasoning behind the chosen threshold value for triggering the alert. Is it based on historical data, best practices, or capacity planning?
- If the gauage metric keeps increasing, it means we are not dispatching any events. Having a low threshold should signal issues early on, before we see failures like lack of resources.
> Describe the expected behavior of the metric under normal conditions. This helps identify situations where the alert might be falsely firing.
- This metric should go up and down as pending events are queued and dispatched.
- Some peaks are expected during traffic peak times.
- The `Pending events` panels should have a relatively low 2 digit number.

## Alert Behavior

> Expected frequency of the alert. Is it a high-volume alert or expected to be rare?
- Should be rare.
> Show historical trends of the alert firing e.g  Kibana dashboard
- N/A (new alert)

## Severities

> Guidance for assigning incident severity to this alert
- `s4`
> Who is likely to be impacted by this cause of this alert?
- Customers pushing/pulling images to the container registry.
> Things to check to determine severity
- [Service overview](https://dashboards.gitlab.net/d/registry-main/registry3a-overview?orgId=1)
- Escalate if service is degraded for a prolonged period of time.

## Verification

- [Metric explorer](https://dashboards.gitlab.net/goto/7BwhS-9Ig?orgId=1)
- [Registry logs](https://log.gprd.gitlab.net/app/r/s/mUjiG)
- [`registry-main/registry-overview`](https://dashboards.gitlab.net/d/registry-main/registry-overview)
- [`registry-notifications/webhook-notifications-detail`](https://dashboards.gitlab.net/d/registry-notifications/webhook-notifications-detail)
- [`api-main/api-overview`](https://dashboards.gitlab.net/d/api-main/api-overview)
- [`cloudflare-main/cloudflare-overview`](https://dashboards.gitlab.net/d/cloudflare-main/cloudflare-overview)
- [Rails API logs](https://log.gprd.gitlab.net/app/r/s/nxwUF).

## Recent changes

- [Workloads MRs for "Service::Container Registry"](https://gitlab.com/gitlab-com/gl-infra/k8s-workloads/gitlab-com/-/merge_requests?scope=all&state=opened&label_name[]=Service%3A%3AContainer%20Registry)
> How to properly roll back changes
- Check the changelog in the MR that updated the registry.
- Review MRs included in the related release issue
- If any MR has the label ~cannot-rollback applied, a detailed description should exist in that MR.
- Otherwise, proceed to revert the commit and watch the deployment.
- Review the dashboards and expect the metric to go back to normal.


## Troubleshooting

- Registry [troubleshooting](../webhook-notifications.md#troubleshooting)

## Possible Resolutions

- > Links to past incidents where this alert helped identify an issue with clear resolutions

## Dependencies

- Rails API
- Cloudflare/firewall rules

# Escalation

> Slack channels where help is likely to be found:
- [g_container_registry](https://gitlab.enterprise.slack.com/archives/CRD4A8HG8)
- [s_package](https://gitlab.enterprise.slack.com/archives/CAGEWDLPQ)

# Definitions

- > Link to the definition of this alert for review and tuning
- > Advice or limitations on how we should or shouldn't tune the alert
- > Link to edit this playbook
- [Update the template used to format this playbook](https://gitlab.com/gitlab-com/runbooks/-/edit/master/docs/template-alert-playbook.md?ref_type=heads)

# Related Links

- [Related alerts](https://gitlab.com/gitlab-com/runbooks/-/tree/master/docs/registry/alerts?ref_type=heads).
- [Documentation](https://gitlab.com/gitlab-com/runbooks/-/tree/master/docs/registry/README.md?ref_type=heads).