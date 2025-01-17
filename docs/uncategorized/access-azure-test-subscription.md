# Azure Test Subscription

**Table of Contents**

[TOC]

Due to requests like: [AKS testing](https://gitlab.com/gitlab-com/access-requests/issues/526) and [customer testing needs](https://gitlab.com/gitlab-com/access-requests/issues/537), we now have a testing Subscription in Azure for the GitLab team.

The Subscription is called Pay-As-You-Go Testing and is tied to the existing Default directory for user access.

Requests for access should go through the existing [Access Request Process](https://gitlab.com/gitlab-com/access-requests)

For the infrastructure and IT/ops teams, access can be provisioned by:

1. Logging in to the [Azure portal](https://portal.azure.com)
2. Going to All Services > Identity > Users > New Guest User
    - **Note**: The user may already be a member, in which case you may proceed directly to adding the IAM role in the next step.
3. Once the invite is accepted, under Home > Subscriptions > Pay-As-You-Go > IAM, add the new user to the Contributor Role for the Pay-As-You-Go Testing Subscription
