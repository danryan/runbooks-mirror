# Engineer On Call (EOC)

To start with the right foot let's define a set of tasks
that are nice things to do before you go any further in your week.

By performing these tasks we will keep the [broken window effect](https://en.wikipedia.org/wiki/Broken_windows_theory)
under control, preventing future pain and mess.

## Going on call

Here is a suggested checklist of things to do at the start of an on-call shift:

- *Change Slack Icon*: Click name. Click `Set status`. Click grey smile face.
  Type `:pagerduty:`. Set `Clear after` to end of on-call shift. Click `Save`
- *Join alert slack channels if not already a member*:
  - `#production`
  - `#alerts-prod-abuse`
  - `#tenable-notifications`
  - `#marquee_account_alrts`
- *Turn on slack channel notifications for these slack channels for
  `All new messages`*:
  - `#production`
  - `#incident-management`
- At the start of each on-call day, read the on-call handover issue that has
  been assigned to you by the previous EOC, and familiarize yourself with any
  ongoing incidents.

At the end of a shift:

- *Turn off slack channel notifications*: Open notification preferences in monitored Slack channels from the previous checklist and return alerts to the desired values.
- *Leave noisy alert channels*: `/leave` alert channels (It's good to stay in `#alerts` and `#alerts-general`)
- Comment on any open S1 incidents at: https://gitlab.com/gitlab-com/gl-infra/production/issues?scope=all&utf8=✓&state=opened&label_name%5B%5D=incident&label_name%5B%5D=S1
- At the end of each on-call day, post a quick update in slack so the next person is aware of anything ongoing, any false alerts, or anything that needs to be handed over.

## Going off call

- Take a deep breath! You did it!
- Review your incidents and see if any of them need corrective actions, to be marked as resolved, or reviews filled out.
- Take note of any alerts that were not productive and use [these resources](../../docs/monitoring/alert_tuning.md) to make notifications more helpful.
- Schedule some down time to recouperate and relax. Being on call is stressful, even on a good week.

## Things to keep an eye on

### On-call issues

First check [active production incident issues][active-production-incident-issues]
to familiarize yourself with what has been happening lately. Also, keep an eye
on the [#production][slack-production] and
[#incident-management][slack-incident-management] channels for discussion around
any on-going issues.

### Useful Dashboard to keep open

- [GitLab Triage](https://dashboards.gitlab.net/d/RZmbBr7mk/gitlab-triage?orgId=1)

### Alerts

Start by checking how many alerts are in flight right now

- go to the [fleet overview dashboard](https://dashboards.gitlab.net/d/mnbqU9Smz/fleet-overview?orgId=1) and check the number of Active Alerts, it should be 0. If it is not 0
    - go to the alerts dashboard and check what is being triggered
        - [azure][prometheus-azure]
        - [gprd prometheus][prometheus-gprd]
        - [gprd prometheus-app][prometheus-app-gprd]
    - watch the [#alerts][slack-alerts] and [#alerts-general][slack-alerts-general] channels for alert notifications;
      each alert here should point you to the right [runbook][runbook-repo] to fix it.
    - if they don't, you have more work to do.
    - be sure to create an issue, particularly to declare toil so we can work on it and suppress it.

### Prometheus targets down

Check how many targets are not scraped at the moment. alerts are in flight right now, to do this:

- go to the [fleet overview dashboard](https://dashboards.gitlab.net/dashboard/db/fleet-overview) and check the number of Targets down. It should be 0. If it is not 0
    - go to the [targets down list] and check what is.
        - [azure][prometheus-azure-targets-down]
        - [gprd prometheus][prometheus-gprd-targets-down]
        - [gprd prometheus-app][prometheus-app-gprd-targets-down]
    - try to figure out why there is scraping problems and try to fix it. Note that sometimes there can be temporary scraping problems because of exporter errors.
    - be sure to create an issue, particularly to declare toil so we can work on it and suppress it.

### Security

If you find any abnormal or suspicious activity during the course of your on call on-call rotation, please do not hesitate to [contact security](https://handbook.gitlab.com/handbook/security/security-operations/sirt/engaging-security-on-call/).

## Rotation Schedule

We use [PagerDuty](https://gitlab.pagerduty.com) to manage our on-call rotation schedule and alerting for emergency issues.
We currently have a split schedule between
[EMEA][pagerduty-emea], [AMER][pagerduty-amer], and [APAC][pagerduty-apac] for on-call rotations in each geographical region.

The AMER, APAC, and EMEA schedules have a [shadow schedule][pagerduty-shadow]
which we use for on-boarding new engineers to the on-call rotations.

When a new engineer joins the team and is ready to start shadowing for an on-call rotation,
[overrides][pagerduty-overrides] should be enabled for the relevant on-call hours during that rotation.
Once they have completed shadowing and are comfortable/ready to be inserted into the primary rotations,
update the membership list for the appropriate schedule to [add the new team member][pagerduty-add-user].

This [pagerduty forum post][pagerduty-shadow-schedule] was referenced when setting up the
[blank shadow schedule][pagerduty-blank-schedule] and initial [overrides][pagerduty-overrides] for on-boarding new team members.

### Creating temporary PagerDuty maintenance windows

A temporary maintenance window may be created at any time using the `/chatops run pager pause`
command in the [`#production` slack channel](https://gitlab.slack.com/archives/C101F3796). The
default window duration is `1 hour`. To schedule a window for another duration a
[`ruby chronic`-compatible time specification](https://github.com/mojombo/chronic#examples) can be used like so: `--duration="2 hours"`.

For more options, use `/chatops run pager --help`:

```
Pause or resume pages.

Usage: pager <pause|resume> [options]

Options:

  -h, --help           Shows this help message
  --duration           Duration of window; default: 1 hour
  --environment        Environment [production,staging,test]; default: production
  --filter-by-creator  Filter maintenance windows by creator; default: false
```

Currently a maintenance window cannot be created for a duration smaller than 1 minute, according
to undocumented implementation in the PagerDuty API.


[on-call-issues]:                   https://gitlab.com/gitlab-com/gl-infra/reliability/-/issues?scope=all&utf8=%E2%9C%93&&state=all&label_name[]=oncall
[active-production-incident-issues]:https://gitlab.com/gitlab-com/gl-infra/production/issues?state=open&label_name[]=Incident::Active

[pagerduty-add-user]:               https://support.pagerduty.com/docs/editing-schedules#section-adding-users
[pagerduty-amer]:                   https://gitlab.pagerduty.com/schedules#POL1GSQ
[pagerduty-apac]:                   https://gitlab.pagerduty.com/schedules#PF02RF0
[pagerduty-emea]:                   https://gitlab.pagerduty.com/schedules#P40KYLY
[pagerduty-shadow]:                 https://gitlab.pagerduty.com/schedules#PZEBYO0
[pagerduty-blank-schedule]:         https://community.pagerduty.com/t/creating-a-blank-schedule/212
[pagerduty-shadow-schedule]:        https://community.pagerduty.com/t/creating-a-shadow-schedule-to-onboard-new-employees/214
[pagerduty-overrides]:              https://support.pagerduty.com/docs/editing-schedules#section-create-and-delete-overrides

[prometheus-azure]:                 https://prometheus.gitlab.com/alerts
[prometheus-azure-targets-down]:    https://prometheus.gitlab.com/consoles/up.html
[prometheus-gprd]:                  https://prometheus.gprd.gitlab.net/alerts
[prometheus-gprd-targets-down]:     https://prometheus.gprd.gitlab.net/consoles/up.html
[prometheus-app-gprd]:              https://prometheus-app.gprd.gitlab.net/alerts
[prometheus-app-gprd-targets-down]: https://prometheus-app.gprd.gitlab.net/consoles/up.html

[runbook-repo]:                     https://gitlab.com/gitlab-com/runbooks

[slack-alerts]:                     https://gitlab.slack.com/channels/alerts
[slack-alerts-general]:             https://gitlab.slack.com/channels/feed_alerts-general
[slack-alerts-gstg]:                https://gitlab.slack.com/channels/alerts-gstg
[slack-incident-management]:        https://gitlab.slack.com/channels/incident-management
[slack-production]:                 https://gitlab.slack.com/channels/production
