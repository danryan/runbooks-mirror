<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [About](#about)
- [Repository](#repository)
- [How it is setup](#how-it-is-setup)
- [Availability Issues](#availability-issues)
- [Escalation](#escalation)
- [Fastly](#fastly)
- [Azure](#azure)
- [Chef](#chef)
- [AWS DNS entries (production console)](#aws-dns-entries-production-console)
- [gitlab-ci.yml config in www-gitlab-com](#gitlab-ciyml-config-in-www-gitlab-com)

<!-- markdown-toc end -->

# About

The [about.gitlab.com](https://gitlab.com/gitlab-com/www-gitlab-com) website is the go-to place to learn pretty much everything about GitLab: the product, pricing, various resources, blogs, support and most importantly our handbook

# Repository

Here is the project repository behind about.gitlab.com: <https://gitlab.com/gitlab-com/www-gitlab-com>

# How it is setup

- The about.gitlab.com project is hosted on [about.gitlab.com](https://console.cloud.google.com/storage/browser/about.gitlab.com?forceOnBucketsSortingFiltering=false&authuser=1&folder=&organizationId=&project=gitlab-production) GCS bucket. The website configuration has it that it points to an `index.html` file at the root level.
- The DNS is setup on Fastly. (You can get the Fastly login credentials from 1Password)

# Availability Issues

### about.gitlab.com is down

If an issue such as: <https://gitlab.com/gitlab-com/gl-infra/production/-/issues/2087> occurs:

1. Check the pipeline to see if there has been a recent deployment to which you can co-relate the issue you are seeing
2. Check Fastly to see if there has been a recent change
3. Check the GCS bucket to see if there is anything abnormal

### Users experiencing 503 errors

Example incident: <https://gitlab.com/gitlab-com/gl-infra/production/-/issues/5230>.

Full error might appear as: `Error 503 No healthy IP available for the backend`

1. Goto manage.fastly.com > about.gitlab.com > Stats
1. Check the Errors dashboard.
1. You can find which datacenters are affected by selecting 1 datacenter at a time from the dropdown menu that defaults to `All datacenters`.

# Escalation

about.gitlab.com has a section dedicated to on-call support for the handbook. It is located at: <https://about.gitlab.com/handbook/about/on-call>.

# Fastly

The [about.gitlab.com Fastly service](https://manage.fastly.com/configure/services/652MHuIME217ZATbh7vFWC)
is configured to use the [about.gitlab.com Google Cloud Storage bucket](https://console.cloud.google.com/storage/browser/about.gitlab.com?project=gitlab-production)
as an origin. It does not use the about-src.gitlab.com host at all.

```
$ dig +short about.gitlab.com
151.101.194.49
151.101.130.49
151.101.2.49
151.101.66.49
$ whois 151.101.194.49 # Fastly
```

# Azure

Terraform code for Azure infra is deprecated and no longer maintained, it hasn't been used in a long time so any changes should be made manually through the WebUI

```
$ dig +short about-src.gitlab.com
40.79.82.214
$ whois 40.79.82.214   # Azure
$ ssh about-src.gitlab.com # ssh keys are put there by Chef

```

Ubuntu 14.04

# Chef

```
$ knife node show about.gitlab.com
Node Name:   about.gitlab.com
Environment: _default
FQDN:        about.gitlab.com
IP:          40.79.82.214
Run List:    role[base-debian], role[about-gitlab-com]
Roles:       base-debian, base-debian-no-chef-client, base, syslog-client, gitlab-security, about-gitlab-com
Recipes:     gitlab-server::ohai-plugin-path, gitlab-server::packages, gitlab-server::timezone-utc, gitlab-server::disable_history, gitlab-server::cron-check-authorized_keys2, gitlab-server::aws-get-public-ip, gitlab-server::get-public-ip, apt::unattended-upgrades, gitlab-server::locale-en-utf8, gitlab-server::ntp-client, gitlab-server::screenrc, gitlab-server::updatedb, gitlab_users::default, gitlab_sudo::default, gitlab-openssh, gitlab-openssh::default, chef_client_updater, chef_client_updater::default, chef-client, chef-client::default, gitlab-exporters::node_exporter, gitlab-server::rsyslog_client, postfix::_common, postfix::aliases, gitlab-server::debian-editor-vim, gitlab-server::dpkg-defaults, gitlab-iptables, gitlab-iptables::default, gitlab-security::rkhunter, gitlab-security::auditd, cookbook-about-gitlab-com::default, apt::default, gitlab-server::timesync, sudo::default, openssh::default, chef-client::service, chef-client::init_service, gitlab-exporters::default, gitlab-exporters::chef_client, ark::default, runit::default, postfix::_attributes, iptables-ng::install, iptables-ng::manage, cookbook-about-gitlab-com::runner, cookbook-about-gitlab-com::nginx, gitlab-vault::default, chef-vault::default
Platform:    ubuntu 14.04
Tags:
```

relevant bits of config:

- node-exporter (there are no other exporters, we do not ship logs anywhere)
- secrets in gitlab-vault (tls certs)
- nginx
- `about.gitlab-review.app` nginx config, contains config for review apps (which use `<branch_name>.about.gitlab-review.app`)
- `redirects` nginx config, it redirects four old links, almost never changes
- gitlab-runner (only installs the package, gitlab-runner config or gitlab-runner register command are not managed with Chef!)
- cron to prune review apps

# AWS DNS entries (production console)

about-src.gitlab.com - vm in Azure

about.gitlab.com - fastly
4 A records
4 AAAA records
1 global-sign-domain

# gitlab-ci.yml config in www-gitlab-com

[url](https://gitlab.com/gitlab-com/www-gitlab-com/blob/master/.gitlab-ci.yml)

Most jobs use runners with `gitlab-org` tag (general purpose docker runners)

There are three deploy jobs:

- Upload the prod version of the website to GCS (only master).
- Deploy review apps (only merge requests)
- Stop deploying review apps (manual)

The last two use the runner on about-src.gitlab.com, it's a shell runner.
All three deploy websites content by rsyncing artifacts generated using MiddleMan in previous jobs
