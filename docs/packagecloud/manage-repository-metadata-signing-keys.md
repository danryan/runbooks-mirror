# GPG Keys for Repository Metadata Signing

**Table of Contents**

[TOC]

[Packagecloud](https://packagecloud.io), the application that powers packages.gitlab.com, supports two different types of GPG signatures: **packages** and **repository metadata**.

This document is concerned with **repository metadata signing** keys. For package signing, see [manage package signing keys](../packaging/manage-package-signing-keys.md).

## Repository Metadata

Packagecloud signs repository metadata using a private key that is either generated by Packagecloud or generated
externally and configured in the app. This is a security feature that gives our users certainty that the repository
metadata was generated by us.

We manage the key externally so we provide the private key to Packagecloud using a Kubernetes secret. This secret is
synced from Vault, which is ultimately where the key lives and where any changes need to take place.
Read on to find out how to make changes to the key (e.g., due to expiry extension or key rotation).

## Location of the Key

The private key lives in [Vault](https://vault.gitlab.net) under the path `k8s/ops-gitlab-gke/packagecloud/gpg`.

## Process

This process should be carried out by a member of the [Distribution team](https://about.gitlab.com/handbook/engineering/development/enablement/systems/distribution/).

1. Create AR to **request** read/write access to the secret in Vault:

    1. [Create access request issue](https://gitlab.com/gitlab-com/team-member-epics/access-requests/-/issues/new?issuable_template=Individual_Bulk_Access_Request)
    1. For _System(s)_, specify _Okta Group Membership_.
    1. For _System Name_, specify: `Okta Group: Team - Distribution - Packagecloud Repository Metadata Signing Key`.
    1. For _Justification for this access_, specify:

        ```text
        Temporary group membership required to update the Packagecloud repository metadata
        signing key in Vault. Process outlined in https://gitlab.com/gitlab-com/runbooks/-/tree/master/docs/packagecloud/manage-repository-metadata-signing-keys.md.
        ```

    1. Follow the instructions in the issue to get your AR approved & actioned by the provisioners.

1. [Generate GPG keys pair](../packaging/manage-package-signing-keys.md#generating-the-gpg-keys-pair) **OR** [extend expiry
   date on existing keys](../packaging/manage-package-signing-keys.md#extending-key-expiration)

    If you are looking to rotate the key, then you should **generate a new GPG key pair**.

    If the current key is due to expire soon and you are happy to keep the existing key, then you can just **extend the
    expiry**. You will need to import the existing private key, which you can obtain by going to
    <https://vault.gitlab.net> (sign-in using Okta) and accessing `k8s/ops-gitlab-gke/packagecloud/gpg`. If you see an
    access denied message then you will need to reach out to #it_help and confirm that you were added to the correct
    group.

    The outcome of this step should be a new or extended private key.

1. Once your AR has been actioned, update the secret in Vault:

    1. Open <https://vault.gitlab.net> and sign-in using Okta.
    1. Head to the path: `k8s/ops-gitlab-gke/packagecloud/gpg`.
    1. Click on _Create new version_.
    1. Update the value of `private_key` with the contents of your exported private key.
    1. Click _Save_.
    1. Take note of the `version` of the secret (next to _Create new version_). You'll need this next!

1. Update [gitlab-helmfiles](https://gitlab.com/gitlab-com/gl-infra/k8s-workloads/gitlab-helmfiles):

    1. Update version to the new version number from the previous
      step:
      [here](https://gitlab.com/gitlab-com/gl-infra/k8s-workloads/gitlab-helmfiles/-/blob/0b89319cf24f82bdeb978b9d6f101f7c7d73483c/releases/packagecloud/values-secrets/ops.yaml.gotmpl#L75)
      and [here](https://gitlab.com/gitlab-com/gl-infra/k8s-workloads/gitlab-helmfiles/-/blob/0b89319cf24f82bdeb978b9d6f101f7c7d73483c/releases/packagecloud/values-secrets/ops.yaml.gotmpl#L86).
    1. Update `secretName` to match: [here](https://gitlab.com/gitlab-com/gl-infra/k8s-workloads/gitlab-helmfiles/-/blob/0b89319cf24f82bdeb978b9d6f101f7c7d73483c/releases/packagecloud/ops.yaml.gotmpl#L64).
    1. File an MR with the above changes and have someone in `#infrastructure-lounge` review/approve/merge it for you.

1. Validation:

    Once the `gitlab-helmfiles` CI pipeline has finished, you're ready to do a quick test:

    ```sh
    $ curl -s https://packages.gitlab.com/gpg.key | gpg --show-key
    pub   rsa4096 2020-03-02 [SC] [expires: 2024-03-01]
          F6403F6544A38863DAA0B6E03F01618A51312F3F
    uid                      GitLab B.V. (package repository signing key) <packages@gitlab.com>
    sub   rsa4096 2020-03-02 [E] [expires: 2024-03-01]
    ```

    Check that the fingerprint & expiry matches your new/extended key.

1. Create AR to **revoke** read/write access to the secret in Vault:

    1. [Create access change issue](https://gitlab.com/gitlab-com/team-member-epics/access-requests/-/issues/new?issuable_template=Access_Change_Request)
    1. For _System_, specify _Okta Group Membership_.
    1. For _System Name_, specify: `Okta Group`.
    1. For _Other details_, specify: `Group Name: Team - Distribution - Packagecloud Repository Metadata Signing Key`.
    1. For _Justification for this access change/removal_, specify:

        ```text
        Temporary group membership no longer required. See
        https://gitlab.com/gitlab-com/runbooks/-/tree/master/docs/packagecloud/manage-repository-metadata-signing-keys.md for more info.
        ```

    1. Assign the issue to the Okta provisioners as no approval is needed for access removal.

1. [Clean up after yourself](../packaging/manage-package-signing-keys.md#purging-local-copies).
