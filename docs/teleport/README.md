# Teleport

[Teleport](https://goteleport.com/docs/) is an *Access Management Platform*.

<!-- MARKER: do not edit this section directly. Edit services/service-catalog.yml then run scripts/generate-docs -->

**Table of Contents**

[[_TOC_]]

# Teleport Access Platform Service

* **Alerts**: <https://alerts.gitlab.net/#/alerts?filter=%7Btype%3D%22teleport%22%2C%20tier%3D%22inf%22%7D>
* **Label**: gitlab-com/gl-infra/production~"Service::TeleportCore"

## Logging

* []()

## Troubleshooting Pointers

* [Set up bastions for Release managers](../bastions/rm-bastion-access.md)
* [Accessing the Rails Console as an SRE](../console/access.md)
* [CustomersDot main troubleshoot documentation](../customersdot/overview.md)
* [Container Registry database post-deployment migrations](../registry/db-post-deployment-migrations.md)
* [Connecting To a Database via Teleport](Connect_to_Database_Console_via_Teleport.md)
* [Connecting To a Rails Console via Teleport](Connect_to_Rails_Console_via_Teleport.md)
* [Teleport Administration](teleport_admin.md)
* [Teleport Approver Workflow](teleport_approval_workflow.md)
* [Teleport Disaster Recovery](teleport_disaster_recovery.md)
* [Access Requests](../uncategorized/access-requests.md)
* [Rails is down](../uncategorized/rails-is-down.md)
* [How to Use Vault for Secrets Management in Infrastructure](../vault/usage.md)
<!-- END_MARKER -->

## Guides

* [Teleport Administration](./teleport_admin.md)
* [Teleport Approver Workflow](./teleport_approval_workflow.md)
* [Teleport Disaster Recovery](./teleport_disaster_recovery.md)
* [How to connect to a Rails Console using Teleport](./Connect_to_Rails_Console_via_Teleport.md)
* [How to connect to a Database console using Teleport](./Connect_to_Database_Console_via_Teleport.md)

## Architecture

The following diagram shows the Teleport architecture for GitLab infrastrucutre.
Some details are omitted for brevity.
Teleport resources, shown in green with Teleport icon, are not technically part of any Google Cloud projects.

![Click on the image to see the image in full size](./images/teleport-arch.png "GitLab Teleport Architecture")
