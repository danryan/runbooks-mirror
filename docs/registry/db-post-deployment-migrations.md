## Context

Until recently the registry only had support for regular database schema migrations. After completing the GitLab.com registry upgrade/migration ([gitlab-org&5523](https://gitlab.com/groups/gitlab-org/-/epics/5523)), we're now in a position where the database has grown enough to make simple changes (like creating new indexes) take a long time to execute, so we had to introduce support for post-deployment migrations.

Regular schema migrations are automatically applied by the registry helm chart using a migrations job, introduced in [gitlab-org/charts/gitlab#2566](https://gitlab.com/gitlab-org/charts/gitlab/-/issues/2566). The mid/long-term goal is to have a similar automation for post-deployment migrations ([gitlab-org/charts/gitlab#3926](https://gitlab.com/gitlab-org/charts/gitlab/-/issues/3926)).

Meanwhile, we're already feeling the need to ship post-deployment migrations, so we had to move forward with a short-term solution. This implies skipping any post-deployment migrations during deployments and then raising a change request to have these manually applied from within a registry instance after deploying a version that includes new post-deployment migrations.

This document provides instructions for SREs to apply post-deployment migrations.

## Applying post-deployment migrations

This should be done from within a registry instance in K8s, using the built-in `registry` CLI. If needed, you can look at the relevant CLI documentation [here](https://gitlab.com/gitlab-org/container-registry/-/blob/master/docs-gitlab/database-migrations.md#administration).

1. Confirm that the registry version indicated in the Change Request matches the one (and there is only one) running in the target environment ([dashboard](https://dashboards.gitlab.net/d/registry-app/registry-application-detail?orgId=1&from=now-5m&to=now&viewPanel=3));

1. Connect to the target cluster for which maintenance is occurring ([runbook](https://gitlab.com/gitlab-com/runbooks/-/blob/master/docs/kube/k8s-oncall-setup.md#kubernetes-api-access));

1. Find the oldest container registry Pod (ignore Pods that have `-migrations-` in the name!):

   ```sh
   kubectl get pods -n gitlab -l app=registry
   ```

1. Access the pod:

   ```sh
   kubectl exec -it <pod_name> -- sh
   ```

1. List pending migrations:

   ```sh
   registry database migrate status /etc/docker/registry/config.yml
   ```

   You should see something like this:

   ```text
   +---------------------------------------------------------------------------------+--------------------------------------+
   |                                    MIGRATION                                    |               APPLIED                |
   +---------------------------------------------------------------------------------+--------------------------------------+
   | 20210503145024_create_top_level_namespaces_table                                | 2022-11-29 14:12:58.477128 +0000 WET |
   | 20220803114849_update_gc_track_deleted_layers_trigger                           | 2022-11-29 14:13:00.209522 +0000 WET |
   | ...                                                                             | ...                                  |
   | 20221123174403_post_add_layers_simplified_usage_index_batch_1 (post deployment) |                                      |
   +---------------------------------------------------------------------------------+--------------------------------------+
   ```

   In this example, there is one pending post-deployment migration named `20221123174403_post_add_layers_simplified_usage_index_batch_1`. You know it's pending because `APPLIED` is empty. You know it's a post-deployment because of the `(post deployment)` suffix.

1. Confirm that there are no pending regular migrations in the list above;

1. Confirm that the number and name of pending post-deployment migrations matches those described in the change request;

1. Halt the execution if any of the above are false;

1. Proceed to apply post-deployment migrations:

   ```sh
   registry database migrate up /etc/docker/registry/config.yml
   ```

   You should see something like this:

   ```text
   20221123174403_post_add_layers_simplified_usage_index_batch_1
   OK: applied 1 migrations
   ```

1. Wait for the above to complete and confirm there are no pending migrations:

   ```sh
   registry database migrate status /etc/docker/registry/config.yml
   ```

   You should see something like this:

   ```text
   +---------------------------------------------------------------------------------+--------------------------------------+
   |                                    MIGRATION                                    |               APPLIED                |
   +---------------------------------------------------------------------------------+--------------------------------------+
   | 20210503145024_create_top_level_namespaces_table                                | 2022-11-29 14:12:58.477128 +0000 WET |
   | 20220803114849_update_gc_track_deleted_layers_trigger                           | 2022-11-29 14:13:00.209522 +0000 WET |
   | ...                                                                             | ...                                  |
   | 20221123174403_post_add_layers_simplified_usage_index_batch_1 (post deployment) | 2022-12-14 12:31:57.42551 +0000 WET  |
   +---------------------------------------------------------------------------------+--------------------------------------+
   ```

   Note that `APPLIED` is no longer empty.