# Breakglass

[[_TOC_]]

We follow the [Principle of Least Privilege](https://csrc.nist.gov/glossary/term/least_privilege) whereby SREs don't have default read/write access to Cells infrastructure in GCP.  This helps limit blast radius in case of security
incidents or misconfigurations of running scripts locally to production.  We use [Privileged Access Manager (PAM)][PAM] to provide short lived access to GCP via
the console or `gcloud`.

## When to escalate

```mermaid
---
title: PAM access entitlements
---
flowchart TD
    need_access[I need access to Cells]

    is_incident{Are you in
    an incident?}
    is_change_incident{Need changes
    to fix an incident?}
    is_change_normal{Need to
    make changes?}
    is_specific_cell{Do you know which Cell
    you need to look at?}
    is_team_members_available{Are team members
    available?}
    is_change_operational{Do you need to
    make temporary changes
    as part of a CR?}

    iac_change[Make changes through IaC]

    project_read
    project_admin
    project_breakglass
    org_read

    need_access-->is_incident

    is_incident-->|Yes| is_change_incident
    is_change_incident-->|No|project_read
    is_change_incident-->|Yes, need write access to quickly solve incident
    I will sync IaC after|is_team_members_available
    is_team_members_available-->|Yes|project_admin
    is_team_members_available-->|No|project_breakglass

    is_incident-->|No| is_change_normal
    is_change_normal-->|No|is_specific_cell
    is_change_normal-->|Yes|is_change_operational
    is_specific_cell-->|Yes|project_read
    is_specific_cell-->|No|org_read
    is_change_operational-->|Yes|project_admin
    is_change_operational-->|No
    OR
    Yes, but I can make changes through IaC|iac_change
```

## How to escalate

Google provides guides to request access through [the console](https://cloud.google.com/iam/docs/pam-request-temporary-elevated-access#request-grant-console)
and through the [`gcloud` CLI](https://cloud.google.com/iam/docs/pam-request-temporary-elevated-access#request_a_grant_programmatically).

Specific Examples:

- [`org_read`](#org_read)
- [`project_read`](#project_read)
- [`project_admin`](#project_admin)
- [`project_breakglass`](#project_breakglass)
- [amp](#amp)

## Levels of access

### Default Access

By default we give [enough permissions](https://gitlab.com/gitlab-com/gl-infra/cells/tissue/-/blob/702095d2f62f7fc65c3171f87e410432c308987f/terraform/modules/cell-environment/iam.tf) to SREs to view the organization, view projects, and use PAM. For any further action through GCP changes must be made
through IaC or using PAM escalation.

| Cells Dev                                               | Cells Prod                                                      |
|---------------------------------------------------------|-----------------------------------------------------------------|
| ![cells dev overview](./img/cells_dev_org_switcher.png) | ![cells_production_overview](./img/cells_prod_org_switcher.png) |

### Org-wide Access

#### [org_read](https://gitlab.com/gitlab-com/gl-infra/gitlab-dedicated/library/terraform/google-privileged-access-manager/-/blob/346edc2e8c2ecee79b8bf06a23819675d4be644d/predefined-entitlements.tf#L9-L28)

- Get access with `gcloud`:

    ```sh
    # $ORG_ID for dev: `425712905585`
    # $ORG_ID for prod: `1073525295030`
    # $CELL_ENV for dev: `dev`
    # $CELL_ENV for prod: `prod`
    gcloud beta pam grants create \
              --entitlement="org-readonly-entitlement-${CELL_ENV}" \
              --requested-duration="1800s" \
              --justification="$ISSUE_LINK" \
              --location=global \
              --organization="$ORG_ID"
    ```

- Get access with console: [dev](https://console.cloud.google.com/iam-admin/pam/entitlements/my?organizationId=425712905585) | [prod](https://console.cloud.google.com/iam-admin/pam/entitlements/my?organizationId=1073525295030)

This entitlement provides the ability to `list` resources at an org-wide level, but does not provide the ability to `get` details for resources, other than IAM bindings. This is useful for initial
discovery and exploration of the resources available across the org.

### Project Access

#### [project_read](https://gitlab.com/gitlab-com/gl-infra/gitlab-dedicated/library/terraform/google-privileged-access-manager/-/blob/346edc2e8c2ecee79b8bf06a23819675d4be644d/predefined-entitlements.tf#L30-L53)

- Get access with `gcloud`:

    ```sh
    # TENANT_ID: Can be found in the "tenant_id" field in the tenant model in `cells/tissue`.
    # example TENANT_ID="c01j2gdw0zfdafxr6"
    gcloud beta pam grants create \
              --entitlement="gldt-readonly-entitlement-${TENANT_ID}" \
              --requested-duration="1800s" \
              --justification="$ISSUE_LINK" \
              --location=global \
              --project="cell-${TENANT_ID}"
    ```

- Get access with console: [dev](https://console.cloud.google.com/iam-admin/pam/entitlements/my?project=cell-c01j2t2v563b55mswz) | [prod](https://console.cloud.google.com/iam-admin/pam/entitlements/my?project=cell-c01j2gdw0zfdafxr6)

This entitlement provides the ability to view resources within a project scope. This allows you to `list` and `get` resources to discover and describe specific resource configurations, e.g. Viewing
the details for a GKE cluster and its nodes.

#### [project_admin](https://gitlab.com/gitlab-com/gl-infra/gitlab-dedicated/library/terraform/google-privileged-access-manager/-/blob/346edc2e8c2ecee79b8bf06a23819675d4be644d/predefined-entitlements.tf#L55-L110)

- Get access with `gcloud`:

    ```sh
    # TENANT_ID: Can be found in the "tenant_id" field in the tenant model in `cells/tissue`.
    # example TENANT_ID="c01j2gdw0zfdafxr6"
    gcloud beta pam grants create \
              --entitlement="gldt-admin-entitlement-${TENANT_ID}" \
              --requested-duration="1800s" \
              --justification="$ISSUE_LINK" \
              --location=global \
              --project="cell-${TENANT_ID}"
    ```

- Get access with console: [dev](https://console.cloud.google.com/iam-admin/pam/entitlements/my?project=cell-c01j2t2v563b55mswz) | [prod](https://console.cloud.google.com/iam-admin/pam/entitlements/my?project=cell-c01j2gdw0zfdafxr6)

Admin access provides typical operational readwrite abilities for managing cell infrastructure.

This level of access requires an approver, and typically will also link to an issue detailing why the access is required.
We should prefer making changes through IaC wherever possible.

#### [project_breakglass](https://gitlab.com/gitlab-com/gl-infra/gitlab-dedicated/library/terraform/google-privileged-access-manager/-/blob/346edc2e8c2ecee79b8bf06a23819675d4be644d/predefined-entitlements.tf#L55-L110)

- Get access with `gcloud` access:

    ```sh
    # TENANT_ID: Can be found in the "tenant_id" field in the tenant model in `cells/tissue`.
    # example TENANT_ID="c01j2gdw0zfdafxr6"
    gcloud beta pam grants create \
              --entitlement="gldt-breakglass-entitlement-${TENANT_ID}" \
              --requested-duration="1800s" \
              --justification="$ISSUE_LINK" \
              --location=global \
              --project="cell-${TENANT_ID}"
    ```

- Get access with console: [dev](https://console.cloud.google.com/iam-admin/pam/entitlements/my?project=cell-c01j2t2v563b55mswz) | [prod](https://console.cloud.google.com/iam-admin/pam/entitlements/my?project=cell-c01j2gdw0zfdafxr6)

Breakglass provides the same level of access as the [`project_admin`](#project_admin) entitlement.

This access does not require an approver. The entitlement is intended to be used
during an incident response when there is low team member availability.

We should use `breakglass` as a last resort when we need to make an emergency change to speed up incident response.

#### Amp

- Get access with `gcloud`

    ```sh
    # AMP_PROJECT_ID for dev: `amp-b6f1`
    # AMP_PROJECT_ID for prod: `amp-3c0d`
    gcloud beta pam grants create \
                    --entitlement="gld-readonly-entitlement" \
                    --requested-duration="1800s" \
                    --justification="$ISSUE_LINK" \
                    --location=global \
                    --project="amp-3c0d"
    ```

- Get access with console: [dev](https://console.cloud.google.com/iam-admin/pam/entitlements/my?project=amp-b6f1) | [prod](https://console.cloud.google.com/iam-admin/pam/entitlements/my?project=amp-3c0d)

The AMP GCP project has the same entitlements as a Cell, meaning [`project_read`](#project_read), [`proejct_admin`](#project_admin), [`project_breakglass`](#project_breakglass)

[PAM]: https://cloud.google.com/iam/docs/pam-overview
