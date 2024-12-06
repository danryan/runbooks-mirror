# Gitaly servers healthcheck

## Experiment

- Provision new gitaly nodes in the zones that will not be affected by the gameday outage using the multi-project [setup](https://gitlab.com/gitlab-com/runbooks/-/tree/master/docs/disaster-recovery?ref_type=heads#recovery-from-a-zonal-outage).

## Agenda

- Familiarise yourself how to drain the corresponding zonal cluster using set-server-state for the desired zone.
  - <https://gitlab.com/gitlab-com/runbooks/-/blob/master/docs/frontend/haproxy.md#set-server-state>
- Familiarise yourself with how to provision new gitaly nodes using the multi-project setup.
  - <https://gitlab.com/gitlab-com/runbooks/-/tree/master/docs/disaster-recovery?ref_type=heads#recovery-from-a-zonal-outage>
- Discuss hypothesis

## Hypothesis

The engineer on call should get a message in prometheus-alerts that Gitaly is down on the affected nodes.

## Preparation

1. Identify and inform the SRE on-call during that day running gameday.
1. Create a new issue for the gameday, `/change declare` select the gameday issue.

**Note**: If GitLab.com is unavailable, [create a new issue on the ops instance](https://ops.gitlab.net/gitlab-com/gl-infra/production/-/issues/new?issuable_template=change_zonal_recovery) and select the `change_zonal_recovery` template.
