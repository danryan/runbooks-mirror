# Blocking and disabling things in the HAProxy load balancers

## First and foremost

* *Don't Panic*
* Blocking should be in Cloudflare, not at HAProxy. For a general guide on blocking see [the Cloudflare runbook](../cloudflare/managing-traffic.md#when-to-block-and-how-to-block)
* Make a plan for how to test your change - breaking things at the front door would be bad:
  * Test things in a local LB when possible
  * Get a second set of eyes to look at your change / MR

## Examples - how we have blocked before:

* https://ops.gitlab.net/gitlab-cookbooks/chef-repo/commit/30744f5b8fce05acf1f13e813526b3d5b3512cd0

## Background

HAPRoxy is the main load balancer we use, it is configured via the [`gprd-base-lb-fe-config.json`](https://gitlab.com/gitlab-com/gl-infra/chef-repo/-/blob/master/roles/gprd-base-lb-fe-config.json).

## How do I

### Apply a quick configuration?

To apply a quick configuration to the load balancers the way to go is to change the haproxy custom
configuration in the chef repo.
to do so you will need to issue the command `bundle exec rake "edit_role[gitlab-base-lb]"` from the
chef-repo folder with knife properly configured.

The value to change is "https_custom_config", be careful to respect spaces and to keep previous values:
``` json
  "override_attributes": {
    "gitlab-nfs-cluster": {
      "haproxy": {
        "chef_vault": "gitlab-base-lb",
        "server_timeout": "1h",
        "https_custom_config": "  acl mash2k3_uri path_beg -i /mash2k3/mash2k3-repository/raw/\n  http-request deny if mash2k3_uri\n"
      }
    }
```

#### Samples of configurations:

##### Deny a path with the DELETE http method

```
acl is_stop_impersonation  path_beg         /admin/users/stop_impersonation
acl is_delete method DELETE
http-request deny if is_delete is_stop_impersonation
```

##### Block project imports using blacklist

[Example](https://gitlab.com/gitlab-com/gl-infra/chef-repo/-/commit/c8ebc721f17c4cf85a4971de00e1fa655fadb42a)

```
        "blacklist": {
          "uri": {
            "/api/v4/projects/import": "gitlab-com/gl-infra/production/-/issues/XXXX",
            "/import/gitlab_project": "gitlab-com/gl-infra/production/-/issues/XXXX",
```

#### Once the changes are applied

Remember to run the chef-client in all the LBs
`knife ssh -p 2222 -C 1 -a ipaddress role:gitlab-base-lb  'sudo chef-client'`

Note the port 2222 for ssh as the 22 is the one forwarded to git. Also note the `-C 1`
this is to reduce concurrency and only reload 1 LB at a time

### Disable a whole service in a load balancer

A service is a host and port, this is useful when we want to isolate a given worker and get it out of the load balancing rotation.

To do so we will need to run one chef command:

```
knife ssh -p 2222 -a ipaddress -C 2 role:gitlab-base-lb "echo 'disable server https_git/git01.fe.gitlab.com' | sudo socat stdio /run/haproxy/admin.sock"
```

This will issue a `disable server` to the HAProxy administration socket commanding to put the service down for the given server.

#### Enable the service back up

The same technique, but enable instead of disable:

```
knife ssh -p 2222 -a ipaddress -C 2 role:gitlab-base-lb "echo 'enable server https_git/git01.fe.gitlab.com' | sudo socat stdio /run/haproxy/admin.sock"
```
