# GitLab staging environment

The GitLab.com staging environment has a copy of the production database that
is not current, ways to keep staging updates are being discussed but no plan are
yet made to keep it regularly updated.

This environment also contains a copy of some GitLab groups that are on storage
nodes

## What is this for?

The main goal of this environment is to reduce the feedback loop between development and production, and to have a playground where we can deploy RCs without compromising production as a whole.
If you have any idea on how to improve such feedback loop or you are missing any particular thing that you would like

## What is it made of?

For all hosts running in the staging environment see the [host dashboard](https://dashboards.gitlab.net/d/fasrTtKik/hosts?orgId=1&var-environment=gstg&var-prometheus=prometheus-01-inf-gstg).

Access to staging environment is treated the same as production as per
[handbook](https://about.gitlab.com/handbook/engineering/infrastructure/#production-and-staging-access).

## Run a rails console in staging environment

* Having [created your chef user data
  bag](https://ops.gitlab.net/gitlab-cookbooks/chef-repo/blob/master/doc/user-administration.md),
  ensure that "rails-console" is one of your `groups`. See existing data bags
  for examples.
* After the data bag is uploaded you will have console access on instances that
  chef-client has subsequently run on. This may take up to 30m.
* [Configure the ssh bastion hosts](../../bastions/gstg-bastions.md)
* Try to start a console with:

    ```
    ssh yourname-rails@console-01-sv-gstg.c.gitlab-staging-1.internal`
    sudo gitlab-rails console
    ```

## Run a redis console in staging environment

* SSH into the redis host
  * `ssh redis1.staging.gitlab.com`
* Get the redis password with `sudo grep requirepass /var/opt/gitlab/redis/redis.conf`
* Start redis-cli `/opt/gitlab/embedded/bin/redis-cli`
* Authenticate `auth PASSWORD` - replace "PASSWORD" with the retrieved password

## Run a psql console in staging environment

* ssh into the primary database host:
  * `ssh db1.staging.gitlab.com`
* start `gitlab-psql` with the following command:

    ```
    sudo -u gitlab-psql -H sh \
      -c "/opt/gitlab/embedded/bin/psql \
      -h /var/opt/gitlab/postgresql gitlabhq_production"
    ```

## Deploy to staging

Follow the instructions [from the chef-repo](https://ops.gitlab.net/gitlab-cookbooks/chef-repo/blob/master/doc/staging.md)
(to which you need access to deploy anyway)

## ElasticCloud Watcher: NoMethodError

In November 2021, we added an [Elastic watcher](https://gitlab.com/gitlab-com/runbooks/-/merge_requests/4134) to warn developers of `NoMethodError` occuring in the staging environment. Such an error probably means something has gone wrong with the staging environment.

### What to do when you see this watcher alert ?

1. Investigate where the error is coming from by checking the Kibana links for both the Rails, and Sidekiq logs.
1. Open a new issue in `gitlab-org/gitlab`, or comment on an existing issue there is one.

If you discover high severity regression ([severity1 or severity2](https://about.gitlab.com/handbook/engineering/quality/issue-triage/#availability))
on staging, follow the steps
to [block the deployment to production](https://about.gitlab.com/handbook/engineering/releases/#deployment-blockers)

Past related issues have :

- caused a production incident of severity 2 (https://gitlab.com/gitlab-com/gl-infra/production/-/issues/5931)
- been caused by a feature flag rollout in staging (https://gitlab.com/gitlab-org/gitlab/-/issues/346766)
