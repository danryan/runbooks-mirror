# Linux CI/CD Runners fleet deployments

## Recent Deployments

To find recent deployments check the [`chef-repo` Merge
Requests](https://ops.gitlab.net/gitlab-cookbooks/chef-repo/-/merge_requests?scope=all&utf8=%E2%9C%93&state=merged&label_name%5B%5D=group%3A%3Arunner&label_name%5B%5D=deploy)
that are merged.

## Preflight checklist

Before you will start any work

1. [ ] Make sure that you meet [Administrator prerequisites](README.md#administrator-prerequisites) before you will
   start any work.
1. [ ] [Not in a PCL time window](../README.md#production-change-lock-pcl).
1. [ ] [Change Management](https://about.gitlab.com/handbook/engineering/infrastructure/change-management/) issue was
   created for this configuration change.

## What is the deployment in CI Runners fleet case

By deployment we understand updating the version of GitLab Runner.

It may be done as part of Runner's release process (we then follow a detailed checklist from the release issue).
Or it can be done for whatever other reason, for example a rollback after introducing a regression.

## Deployment procedure

> **Notice:** Remember! Runner's deployment **always** requires [Graceful Shutdown](graceful-shutdown.md)!

### Overview

1. Suspend chef-client on the nodes where the deployment will be happening, using the upgrade script.

1. Update the version information in the proper chef role (**after chef is disabled!**, otherwise installation of
   new package will immediately terminate Runner's process which by the users will be considered as an outage!)

1. Commit and push changes. Create the MR in `chef-repo`.

1. Review, approve and merge the MR. Ask someone else who is familiar with Runner's fleet deployments for a review!

1. After the merge pipeline passes the automatically started jobs ensure that you've executed the `apply_to_prod` manual
   job!

1. Run upgrade script on the nodes where the deployment will be happening, using the upgrade script. It will
   automatically restore chef-client, cleanup all docker machine VMs leftover, update APT repositories and finally
   upgrade configuration by the `chef-client` run. In this case this will also force installation of a changes version
   of the GitLab Runner package, which will automatically start the process again.

### Detailed procedure

> **Notice:** Going forward we'll be going through the example of updating our `prmX` version.
>
> Please check the [roles to runners mapping section](README.md#roles-dependency) to find which role you're interested in.

1. **Suspend `chef-client` process on managers being updated**

   For example, to shutdown `chef-client` on `private-runners-manager-X.gitlab.com`, you can execute:

    ```shell
    knife ssh -afqdn 'roles:gitlab-runner-prm' -- 'sudo -i /root/runner_upgrade.sh stop_chef'
    ```

   To be sure that `chef-cilent` process is terminated you can execute:

    ```shell
    knife ssh -afqdn 'roles:gitlab-runner-prm' -- systemctl is-active chef-client
    ```

   Running `/root/runner_upgrade.sh stop_chef` will stop the service and any altering that monitors
   if `chef-client` is not running, whilst leaving a note about the deploy. This will prevent
   anyone from re-enabling the service because of some alerts during deployments of the runner.

1. **Update chef role (or roles)**

   In `chef-repo` directory execute:

    ```shell
    $EDITOR roles/gitlab-runner-prm.json
    ```

   where `gitlab-runner-prm` is a role used by nodes that you are updating.

   In attributes list look for `cookbook-gitlab-runner:gitlab-runner:version` and change it to a version that you want
   to update. It should look like:

    ```json
    "cookbook-gitlab-runner": {
      "gitlab-runner": {
        "repository": "gitlab-runner",
        "version": "13.9.0"
      }
    }
    ```

   If you want to install a Bleeding Edge version of the Runner, you should set the `repository`
   value to `unstable`.

   If you want to install a Stable version of the Runner, you should set the `repository` value to
   `gitlab-runner`.

   As the default version is set in the base role (`gitlab-runner-base`), in the specific roles you should look inside
   of the `override_attributes` section. The exception is `org-ci-base-runner`, as it's not part of the main roles
   structure.

1. Commit and push changes to the remote repository:

    ```shell
    git checkout master && \
        git pull && \
        git checkout -b origin update-prmx-to-13-9-0 && \
        git add roles/gitlab-runner-prm.json && \
        git commit -m "Update prmX runners to 13.9.0" && \
        git push -u origin update-prmx-to-13-9-0 -o merge_request.create -o merge_request.label="deploy" -o merge_request.label="group::runner"
    ```

   After pushing the commit, create, review and work upon a merge of the MR. When the MR gets approved and merged,
   wait for the merge pipeline to finish and double check in the `production_dry_run` job, if the dry-run tries to
   upload only the role file updated above.

   If yes - hit `play` on the `apply_to_prod` job and wait until the job on Chef Server will be updated.

1. **Upgrade all GitLab Runners**

   To upgrade chosen Runners manager, execute the command:

    ```shell
    knife ssh -C1 -afqdn 'roles:gitlab-runner-prm' -- sudo /root/runner_upgrade.sh
    ```

   This will send a stop signal to the Runner. The process will wait until all handled jobs are finished,
   but no longer than 7200 seconds. The `-C1` flag will make sure that only one node using chosen role
   will be updated at a time.

   When the last job will be finished, or after the 7200 seconds timeout, the process will
   be terminated and the script will:
   - remove all Docker Machines that were created by Runner
     (using the `/root/machines_operations.sh remove-all` script),
   - upgrade Runner and configuration with `chef-client` (which will also start the `chef-client` process
     stopped in the first step of the upgrade process),
   - start Runner's process and check if process is running,
   - show the output of `gitlab-runner --version`.

   When upgrade of the first Runner is done, then continue with another one.

1. **Verify the version of GitLab Runner**

   If you want to check which version of Runner is installed, execute the following command:

    ```shell
    knife ssh -afqdn 'roles:gitlab-runner-prm' -- gitlab-runner --version
    ```

   You can also check the [uptime](https://dashboards.gitlab.net/d/000000159/ci?orgId=1&refresh=5m&viewPanel=18)
   and [version](https://dashboards.gitlab.net/d/000000159/ci?viewPanel=163&orgId=1&refresh=5m) on
   CI dashboard.

### Upgrade of whole GitLab.com Runners fleet at once

We're in the process of refactoring configuration of GitLab.com's Runners. Currently, if you want to update
the version on all Runners, it's easiest to edit `gitlab-runner-base` or  `org-ci-base-runner` role. If you want
to update only selected Runner, then you should edit a related role, and set chosen version with `override_attributes`.

If you want to upgrade all Runners of GitLab.com fleet at the same time, then you can use the following script, working
inside of your local copy of [`chef-repo`](https://ops.gitlab.net/gitlab-cookbooks/chef-repo):

```shell
# Suspend chef-client on all deployed nodes
knife ssh -afqdn 'roles:gitlab-runner-base OR roles:org-ci-base-runner' -- 'sudo -i /root/runner_upgrade.sh stop_chef'
knife ssh -afqdn 'roles:gitlab-runner-base OR roles:org-ci-base-runner' -- systemctl is-active chef-client

# Update configuration in roles definition and secrets
git checkout master && git pull
git checkout -b update-runners-fleet
$EDITOR roles/gitlab-runner-base.json
$EDITOR roles/org-ci-base-runner.json
git add roles/gitlab-runner-base.json roles/org-ci-base-runner.json && git commit -m "Update runners fleet to [X.Y.Z-...]"
git push -u origin update-runners-fleet -o merge_request.create -o merge_request.label="deploy" -o merge_request.label="group::runner"
```

When the push will be finished - use the printed URL to open an MR. Double check if the
changes are doing what it should be done for the deployment, and set 'Merge when pipeline succeeds'.
After the branch will be merged, open the pipeline FOR THE MERGE COMMIT (search at
https://ops.gitlab.net/gitlab-cookbooks/chef-repo/pipelines/) and check in the `apply_to_staging` job, if the
dry-run tries to upload only the role file updated above.

If yes - hit `play` on the `apply_to_prod` job and wait until the job on Chef Server will be updated.

You can continue **after the changes are uploaded to Chef Server** by the `apply_to_prod` job.

```shell
# Upgrade Runner's version and configuration on nodes
knife ssh -C1 -afqdn 'roles:roles:org-ci-base-runner' -- sudo /root/runner_upgrade.sh &
knife ssh -C1 -afqdn 'roles:gitlab-runner-gsrm' -- sudo /root/runner_upgrade.sh &
knife ssh -C1 -afqdn 'roles:gitlab-runner-prm' -- sudo /root/runner_upgrade.sh &
knife ssh -C1 -afqdn 'roles:gitlab-runner-srm' -- sudo /root/runner_upgrade.sh &
time wait
```

> **NOTICE:**
> Be aware, that graceful restart of whole CI Runners fleet may take **up to several hours!**
>
> 6-8 hours is the usual timing. Until we'll finish our plan to [use K8S to deploy Runner Managers][k8s-deployment]
> anyone that needs to update/restart Runner on our CI fleet should expect, that the operation will be
> **really long** and that during this time the networking connection can't be terminated.

[gitlab-ce-new-mr]: https://gitlab.com/gitlab-org/gitlab-ce/merge_requests/new
[k8s-deployment]: https://gitlab.com/gitlab-com/gl-infra/infrastructure/issues/4813
