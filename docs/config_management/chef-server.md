# Chef Server

The Chef server is hosted in the `gitlab-ops` GCP project. The server is a
standalone server and runs the embedded PostgreSQL database service locally.

## Cookbook

The [ops-infra-chef](https://ops.gitlab.net/gitlab-cookbooks/chef-repo/-/blob/master/roles/ops-infra-chef.json)
role contains the runlist for the Chef server. The
[gitlab-chef-server](https://gitlab.com/gitlab-cookbooks/gitlab-chef-server)
cookbook installs and manages the Chef services and the Let's Encrypt
certificate renewal.

## Recovery

Snapshots of the data disk are taken every four hours. This should allow some
capacity to restore the Chef server in the event of the VM being deleted/lost.

It is also possible to re-upload all of the cookbooks we need as well as roles
and environments with the `chef-repo` project.

- Terraform can rebuild/replace the load balancer, VM, and DNS.
- Bootstrapping the `gitlab-chef-server` cookbook or rebuilding from a snapshot
    can restore the Chef server service.
- The `chef-repo` project can re-store cookbooks, environments, roles, etc.
