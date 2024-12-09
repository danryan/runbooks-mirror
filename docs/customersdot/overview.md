# CustomersDot main troubleshoot documentation

**Table of Contents**

[TOC]

## Overview

customers.gitlab.com is the site where GitLab customers can manage
their subscription(s) for GitLab.com.

For all availability issues see the **[escalation process for incidents or outages](https://about.gitlab.com/handbook/engineering/development/fulfillment/#escalation-process-for-incidents-or-outages)**.

### Production and Staging

The production and staging environments reside in Google Cloud projects.

* Staging: [gitlab-subscriptions-staging](https://console.cloud.google.com/home/dashboard?project=gitlab-subscriptions-staging)
* Production:
  [gitlab-subscriptions-prod](https://console.cloud.google.com/home/dashboard?project=gitlab-subscriptions-prod)

#### SSH

SSH connectivity to customer-dot VMs is established through Teleport. SREs don't require any additional teleport permissions to access these VMs, and can do so directly as follow:

```shell
$ tsh login --proxy=production.teleport.gitlab.net
$ tsh ssh customers-01-inf-prdsub
```

**NOTE:** if your user ID in Okta differs from that in Chef, you would need to make sure they match in order for this to work. Your Okta user ID is the one that is part of your `@gitlab.com` email address. In this case, you can use:

```
$ tsh ssh <okta_user_id>@customers-01-inf-prdsub
```

##### Break-glass procedure for SSH access

SSH connectivity is normally established through Teleport. In the event that Teleport is unavailable, SREs can connect using SSH to the VMs through the [Identity-Aware Proxy](https://cloud.google.com/iap/docs/using-tcp-forwarding) (IAP). For this to work, you need to file an MR to add the necessary firewall rule:

* [Staging](https://ops.gitlab.net/gitlab-com/gl-infra/config-mgmt/-/blob/846107df82d30b78cb8c36c1410ad766dde9b15f/environments/stgsub/variables.tf#L212)
* [Production](https://ops.gitlab.net/gitlab-com/gl-infra/config-mgmt/-/blob/846107df82d30b78cb8c36c1410ad766dde9b15f/environments/prdsub/variables.tf#L225)
* You might need to refer to
[these instructions](https://gitlab.com/gitlab-org/customers-gitlab-com/-/blob/staging/doc/testing/staging.md#ssh-config)

**NOTE:** Ensure you revert the MR once you're back to using Teleport.

Once the firewall rule has been added, you should be able to do the following:

```sh
gcloud --project <PROJECT_ID> compute ssh <USERNAME>@<VM_NAME> --tunnel-through-iap

# Example:
gcloud --project gitlab-subscriptions-staging compute ssh gservat@customers-01-inf-stgsub --tunnel-through-iap
```

#### CDN

Both staging and production services are proxied through Cloudflare. Refer to
the section for NGINX below for rate limit information.

#### NGINX

The web server on the VM has a rate limit set that should return a 429
when the rate is exceeded. This rate limit is specific to API Seat Requests
and is is managed in
[Ansible](https://gitlab.com/gitlab-org/customersdot-ansible).

#### Logs

* Local Logs
  * NGINX Logs: `/var/log/nginx`
  * PostgreSQL Logs: `/var/log/postgresql`
  * Application Logs (Rails, Puma): `/home/customersdot/CustomersDot/current/log`
  * Sidekiq Logs: `/home/customersdot/CustomersDot/current/log`
* Stackdriver Logs
  * Application Logs from the VM are shipped into Stackdriver in GCP.
  * <https://cloudlogging.app.goo.gl/Jew7kUFaW8SUgeew9>

#### Metrics

Specifications for a Customersdot metric catalog is available at [`metrics-catalog/services/customersdot.jsonnet`](../../metrics-catalog/services/customersdot.jsonnet).

This catalog references the following SLIs:

* `gitlab_sli_customers_dot_requests_total`
* `gitlab_sli_customers_dot_requests_error_total`
* `gitlab_sli_customers_dot_requests_error_apdex_total`
* `gitlab_sli_customers_dot_requests_error_apdex_success_total`
* `gitlab_sli_customers_dot_sidekiq_jobs_total`
* `gitlab_sli_customers_dot_sidekiq_jobs_error_total`
* `gitlab_sli_customers_dot_sidekiq_jobs_error_apdex_total`
* `gitlab_sli_customers_dot_sidekiq_jobs_error_apdex_success_total`

These SLIs were introduced as a [Rails application SLI](https://docs.gitlab.com/ee/development/application_slis/#gitlab-application-service-level-indicators-slis) for CustomersDot (see the [Collector class](https://gitlab.com/gitlab-org/customers-gitlab-com/-/blob/main/lib/metrics/collector.rb) and the [Metrics::Slis class](https://gitlab.com/gitlab-org/customers-gitlab-com/-/blob/main/lib/metrics/slis.rb) for more details).

Two Prometheus instances have been set up for CustomersDot:

* [Prometheus instance for Staging](https://prometheus-gke.stgsub.gitlab.net/graph)
* [Prometheus instance for Production](https://prometheus-gke.prdsub.gitlab.net/graph)

Here is [the main Grafana page for CustomersDot](https://dashboards.gitlab.net/d/customersdot-main/customersdot-overview?orgId=1)

#### Database and Rails console access

Access to the CustomerDot DB and Rails console is via [Teleport](https://gitlab.com/gitlab-org/customers-gitlab-com/-/blob/main/doc/setup/teleport.md)

SREs have SSH access to the CustomerDot VMs for emergency access to the database. Ensure all database changes outside of Teleport or application code are retroactively approved via a change request following the [Infrastructure change request workflow](https://handbook.gitlab.com/handbook/engineering/infrastructure/change-management/#change-request-workflows)

Once you have logged into the Staging or the Production VM, run one of these
commands to open the database or the Rails console:

```bash
gitlab-db # opens the PSQL console.
gitlab-rails-console # opens the Rails console.
```

These scripts can be found in `/usr/local/bin/`.

#### Application provisioning

The provisioning of the CustomersDot application stack is done through the
[CustomersDot Ansible project](https://gitlab.com/gitlab-com/gl-infra/customersdot-ansible). For staging and production, provisioning works through Teleport to reach the VMs. For `stgsub-ref`, it is still direct SSH access through the bastion.

To provision CustomersDot in staging and production manually, please refer to [this documentation](https://gitlab.com/gitlab-com/gl-infra/customersdot-ansible/-/blob/master/doc/readme.md#manual-provisioning).

Alerts related to provisioning are sent to the `#s_fulfillment_status` Slack channel.

#### Deployments

When a pipeline is triggered on the `staging` (default) branch of CustomersDot,
the application is first deployed to Staging then to Production after a delay of
2 hours.

That being said, it is possible to trigger a manual pipeline to deploy to
production right away, should the need to do so arise. To do so, please refer to
[this documentation](https://gitlab.com/gitlab-org/customersdot-ansible/-/blob/master/doc/readme.md#manual-deployment-to-production).

Alerts related to deployments are sent to the `#s_fulfillment_status` Slack channel.

If there's a need to restart services, please refer to this
[restart documentation](https://gitlab.com/gitlab-org/customers-gitlab-com#restart-some-services).

Similar to application provisioning, deployments in staging and production environments work through Teleport (not direct SSH). For `stgsub-ref`, it is still direct SSH via bastion.

### Change Management

Terraform is used to provision the virtual infrastructure for staging and
production:

* [Staging](https://ops.gitlab.net/gitlab-com/gl-infra/config-mgmt/-/tree/main/environments/stgsub)
* [Production](https://ops.gitlab.net/gitlab-com/gl-infra/config-mgmt/-/tree/main/environments/prdsub)

Chef is used essentially to bootstrap user access for users and Ansible.

* [Staging Base](https://gitlab.com/gitlab-com/gl-infra/chef-repo/-/blob/master/roles/stgsub-base.json)
* [Production Base](https://gitlab.com/gitlab-com/gl-infra/chef-repo/-/blob/master/roles/prdsub-base.json)

[Ansible](https://gitlab.com/gitlab-org/customersdot-ansible) is used to deploy the latest code to staging.

### Alerting

At the moment, we rely on [this Uptime Kuma instance for CustomersDot production](https://customersdot.us.to/) for stack monitoring. When an Uptime Kuma alert is created from this instance, it is sent to the `#s_fulfillment_status` Slack channel.

#### Unschedule maintenance

+When Zuora is down (reported to `#s_fulfillment_status`) and CustomersDot is in auto-maintenance mode for longer than 5 minutes, we should create an S3 incident with the CMOC updating the status page based on updates from <https://trust.zuora.com/>.

#### Service degradation during SeatLink traffic hour

[`maintenance_mode_seat_link`](https://gitlab.com/gitlab-org/customers-gitlab-com/-/feature_flags/236/edit) is a feature flag for just blocking seat link traffic. This was implemented because we suspect SeatLink was the cause of several [service degradations](https://gitlab.com/gitlab-com/gl-infra/production/-/issues/8741). If a similar degradation occurs during SeatLink traffic hour (typically around 4 AM UTC), we can enable this flag to block SeatLink traffic.
