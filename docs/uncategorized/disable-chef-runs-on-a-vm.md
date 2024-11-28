## Disable Chef runs on a VM

**Table of Contents**

[TOC]

Occasionally there will be a legitimate reason to stop Chef on a Chef managed
GitLab VM. You should follow the following steps to ensure that it both
communicates the reason for stopping Chef and prevents someone else from
starting the chef-client service when it is intentionally disabled.

**Stopping Chef should never ben done unless it is absolutely needed and should
never be stopped for more than 12 hours without a corresponding issue**

For reference, the current procedure uses scripts provided by Chef recipe
[gitlab-server::chef-client-disabler](https://gitlab.com/gitlab-cookbooks/gitlab-server/-/blob/master/recipes/chef-client-disabler.rb).
Its main purpose is to intercept calls to `chef-client` and put the contextual
information (when, by whom, and why chef-client was disabled) directly in the path
of the hapless user who is trying to run chef-client as part of an unrelated change.

### Disable Chef runs

The disable script takes an optional comment.  Please use it to describe
why chef is being disabled, and include an issue link if available.

To disable both manual and periodic runs of chef-client:

```shell
chef-client-disable 'Manual edits to foo.conf, see issue https://gitlab.com/gitlab-com/gl-infra/production/-/issues/1878'
```

After disabling, any attempt to run chef-client will be intercepted, resulting in output like the following:

```shell
$ sudo chef-client
chef-client is currently disabled.  To re-enable, run: chef-client-enable
Periodic runs via systemd: inactive and disabled on reboot.
Latest log entry from: /var/log/chef-client-disabler-shim.log
2020-04-08 00:00:03 UTC  LOG  (msmiley)  Successfully disabled chef-client.  Comment: Manual edits to foo.conf, see issue https://gitlab.com/gitlab-com/gl-infra/production/-/issues/1878
```

### Enable Chef runs

To re-enable both manual and periodic runs of chef-client:

```shell
chef-client-enable
```

### Checking whether or not chef-client is currently disabled

If you want to just check whether chef-client is disabled without actually running
the real chef-client if it's not disabled, you can use `chef-client-is-enabled`.

```shell
# If enabled:

$ chef-client-is-enabled
chef-client is currently enabled.
Periodic runs via systemd: active and enabled on reboot.

# If disabled:

$ chef-client-is-enabled
chef-client is currently disabled.  To re-enable, run: chef-client-enable
Periodic runs via systemd: inactive and disabled on reboot.
Latest log entry from: /var/log/chef-client-disabler-shim.log
2020-04-08 00:00:03 UTC  LOG  (msmiley)  Successfully disabled chef-client.  Comment: Manual edits to foo.conf, see issue https://gitlab.com/gitlab-com/gl-infra/production/-/issues/1878
```

Its exit value is 0 if chef-client is enabled; otherwise 1.  So if you just want to
survey which hosts are disabled, you can do the following:

```shell
$ knife ssh -C 3 'roles:gstg-base-db-redis-server-cache' 'chef-client-is-enabled >& /dev/null && echo "enabled" || echo "disabled"'
redis-cache-01-db-gstg.c.gitlab-staging-1.internal enabled
redis-cache-02-db-gstg.c.gitlab-staging-1.internal disabled
redis-cache-03-db-gstg.c.gitlab-staging-1.internal enabled
```

### How to manually re-enable

You should not need to do this.

But if for some reason you need to manually undo the effects of `chef-clien-disable`, then
you can do so by replacing the /usr/bin/chef-client symlink.  Either of the following is sufficient:

```shell
$ sudo rm -i /usr/bin/chef-client && ln -s /opt/chef/bin/chef-client /usr/bin/chef-client

# OR:

$ sudo rm -i /usr/bin/chef-client && mv -i /usr/bin/chef-client-alias-when-disabled /usr/bin/chef-client
```

Then you can safely re-enable periodic runs of chef-client:

```shell
$ sudo systemctl start chef-client.service
$ sudo systemctl enable chef-client.service
```


### Historical procedure

The old procedure stops periodic chef-client runs and then
breaks chef-client by moving aside the directory containing
chef-client's credentials and config.

The new procedure is simply to run a script that intercepts
calls to chef-client and gives the caller contextual info,
including any message left by the person who disabled
chef-client (e.g. issue link, what has been locally modified,
etc.).  It also stops the periodic runs of chef-client.

The old procedure (shown below) still works, but it is
incompatible with the new procedure.  (Please do not disable
with one procedure and then try to enable with the other.)

```shell
# Stop periodic runs, and then cripple chef-client by hiding its credentials/config dir.

$ sudo service chef-client stop

# Examples: mv /etc/chef /etc/chef.disabled.because.of.pg.conf.override
#           mv /etc/chef /etc/chef.infra-1231

$ sudo mv /etc/chef /etc/chef.{reason}

# Later, re-enable chef by restoring its credentials dir and restarting periodic runs.

$ sudo mv /etc/chef.{reason} /etc/chef
$ sudo service chef-client start
```
