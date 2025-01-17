## GPRD bastion hosts

**Table of Contents**

[TOC]

### How to start using them

Add the following to your `~/.ssh/config` (specify your username and path to ssh private key):

```
# GCP production bastion host
Host lb-bastion.gprd.gitlab.com
        User                            YOUR_SSH_USERNAME

# gprd boxes
Host *.gitlab-production.internal
        PreferredAuthentications        publickey
        ProxyCommand                    ssh lb-bastion.gprd.gitlab.com -W %h:%p
```

Testing (for example, if you have access to deploy node), output should be like this:

```bash
$> be knife ssh 'roles:gprd-base-deploy-node' 'hostname'
deploy-01-sv-gprd.c.gitlab-production.internal deploy-01-sv-gprd
```

### Console access

There is a dedicated server for console access named
`console-01-sv-gprd.c.gitlab-production.internal`

You can create the following entry in your ssh config for easier access

```
Host gprd-console
        User                    YOUR_SSH_USERNAME-SERVICE_NAME
        StrictHostKeyChecking   no
        HostName                console-01-sv-gprd.c.gitlab-production.internal
        ProxyCommand            ssh lb-bastion.gprd.gitlab.com -W %h:%p
```

where `SERVICE_NAME` is either `rails` or `db`.

See [granting rails or db access](../uncategorized/granting-rails-or-db-access.md) for more
information on how to request console access.

### Host keys

If you care about security enough to compare ssh host keys, here they are, both sha256 and md5 sums:

```
$> ssh-keygen -lf <(ssh-keyscan lb-bastion.gprd.gitlab.com 2>/dev/null)
2048 SHA256:ygMvT9QHMoqxvUULMfvSyo/Lsbx6UEiKoLloFf/BSU0 lb-bastion.gprd.gitlab.com (RSA)
256 SHA256:YjrYlnAlbKv23MI+h4UJGaGU32SWHngXti2ahIEEVz0 lb-bastion.gprd.gitlab.com (ECDSA)
256 SHA256:AOtQEj7qZx3SPq61NU0vxDh9k0f+nccwZOO9ayTkVn8 lb-bastion.gprd.gitlab.com (ED25519)

$> ssh-keygen -E md5 -lf <(ssh-keyscan lb-bastion.gprd.gitlab.com 2>/dev/null)
256 MD5:f7:b3:0c:e1:84:9d:28:1d:6d:84:ff:31:72:56:62:2d lb-bastion.gprd.gitlab.com (ECDSA)
2048 MD5:f4:53:0d:0c:c8:ec:ee:11:18:7a:cc:3a:20:fb:7a:70 lb-bastion.gprd.gitlab.com (RSA)
256 MD5:ab:2b:c8:a7:48:b6:67:1a:cb:94:b0:a3:3f:d6:a0:b3 lb-bastion.gprd.gitlab.com (ED25519)
```

### Tunnel https traffic

gprd public https access is [blocked](https://gitlab.com/gitlab-com/migration/issues/359).
Therefore to connect to gprd, you'll need to set up a tunnel.

To set up such a tunnel:

1. Open a tunnel SSH session:

    ```sh
    ssh -N -L 8443:haproxy-main-01-lb-gprd.c.gitlab-production.internal:443 lb-bastion.gprd.gitlab.com
    ```

    While you leave the SSH session open, this will make it possible to browse to <https://localhost:8443/users/sign_in>,
    although it'll cause a TLS certificate error due domain name mismatch.

1. To be able to visit the server at the correct address, add the following line to `/etc/hosts`:

    ```
    127.0.0.1       gprd.gitlab.com
    ```

    After that you can visit `https://gprd.gitlab.com:8443/users/sign_in`.

    **Caution:** Ensure to _remove_ this line again when the GCP migration is done (after blackout window).

1. If you want to visit the server on port `443`, you can use `socat`.
    Make sure you have `socat` installed, e.g. on macOS run `brew install socat` and then run:

    ```sh
    sudo socat TCP4-LISTEN:443,fork TCP4-CONNECT:localhost:8443
    ```

    Visiting `https://gprd.gitlab.com/users/sign_in` will now work as a charm.

### Tunnel git-over-ssh traffic

Similar to setting up a tunnel for the https traffic, you can set up a
tunnel for git-over-ssh traffic:

1. Open a tunnel SSH session:

    ```sh
    ssh -N -L 2222:haproxy-main-01-lb-gprd.c.gitlab-production.internal:22 lb-bastion.gprd.gitlab.com
    ```

1. Use `socat` to forward from local port `2222` to `22`.

    ```sh
    sudo socat TCP4-LISTEN:22,fork TCP4-CONNECT:localhost:2222
    ```

1. Ensure you have `gprd.gitlab.com` to point to `127.0.0.1` in `/etc/hosts`.

    ```sh
    git clone git@gprd.gitlab.com:gitlab-org/gitlab-ce.git
    ```

1. _Pre-failover:_ When gprd is a Geo secondary, don't forget to set the **push** remote:

    ```sh
    git remote set-url --push origin git@gitlab.com:gitlab-org/gitlab-ce.git
    ```

**Bonus**:

You can create the ssh tunnel for both https **and** ssh at once:

```sh
ssh -N -L 8443:haproxy-main-01-lb-gprd.c.gitlab-production.internal:443 \
       -L 2222:haproxy-main-01-lb-gprd.c.gitlab-production.internal:22 \
       lb-bastion.gprd.gitlab.com
```

Although, you still need to run `socat` twice.

### IAP tunnel alternative

If tunneling over `lb-bastion` is too slow due to high latency, [GCP Identity-Aware Proxy](https://cloud.google.com/iap/) can be used to tunnel TCP directly to the target VM (if allowed), this is faster than SSH over SSH.

Connect directly to console:

```
Host console-01-sv-gprd.c.gitlab-production.internal
        ProxyCommand gcloud compute start-iap-tunnel console-01-sv-gprd 22 --listen-on-stdin --project=gitlab-production --zone=us-east1-c --verbosity=warning
```

### Links

 1. [Issue](https://gitlab.com/gitlab-com/migration/issues/299) describing what was done in scope of the migration project to quickly set them up.
 1. [META](https://gitlab.com/gitlab-com/gl-infra/reliability/-/issues/3995) issue that is a source of truth regarding middleterm/longterm setup.
