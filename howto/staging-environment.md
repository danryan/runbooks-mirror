# GitLab staging environment

We now have the GitLab staging environment.

This environment keeps a copy of the whole production database, ~~anonymised~~, and ~~automatically updated every weekend~~

This environment also contains a copy of the GitLab groups repos accessible through NFS to provide a similar experience to what we actually have in production.

## What is this for?

The main goal of this environment is to reduce the feedback loop between development and production, and to have a playground where we can deploy RCs without compromising production as a whole.
If you have any idea on how to improve such feedback loop or you are missing any particular thing that you would like

## Getting access
* You will need developer ssh access, to get it register an issue with your posix username and your ssh key in the [infrastructure issue tracker](https://gitlab.com/gitlab-com/infrastructure/issues)

## Run a rails console in staging environment

* ssh into any of the staging workers
  * `ssh 191.237.42.73` # worker1
  * `ssh 13.92.88.118` # worker2
* start a rails console issuing the command `sudo gitlab-rails console`

## Run a redis console in staging environment

* ssh into the redis host
  * `ssh 40.117.159.113` # redis1.staging.gitlab.com
* get redis password with `sudo grep requirepass /var/opt/gitlab/redis/redis.conf`
* start redis-cli `/opt/gitlab/embedded/bin/redis-cli`
* authenticate `auth PASSWORD` - replace "PASSWORD" with the retrieved password

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

Follow the instructions [from the chef-repo](https://dev.gitlab.org/cookbooks/chef-repo/blob/master/doc/staging.md)
(to which you need access to deploy anyway)
