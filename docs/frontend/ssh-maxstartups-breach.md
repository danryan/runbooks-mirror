# Possible Breach of SSH MaxStartups

**Table of Contents**

[TOC]

<https://gitlab.com/gitlab-com/gl-infra/reliability/-/issues/7168> provides the context where we discovered this was necessary.
If this document is too brief, refer to that for more detail.

## What to do

Verify that nothing *else* is exploding.
This alert may go off when other major events such as database failures are
preventing ssh authentication from completing (e.g. cannot lookup the ssh key in the DB).
If something else is going on, this alert requires no further specific action.

If nothing else is exploding,
then this alert suggests that the MaxStartups limit is being breached and git+ssh connections are being dropped.
Note that the metric we're alerting on is derived from HAProxy logs and is
a proxy indicator of the underlying problem and thus we may yet find false-positives.
In future (Ubuntu 18.04) we can get better logging out of openssh
that will explicitly tell us when this is happening, and can alert on that instead.
However there is no expectation that we will be able to see how close we are to this limit *before* it happens,
unless we manage to get some stats exporting capability into openssh (a long shot, at best).

**Urgency:** if we've been keeping on top of this, low urgency but important to monitor.
We should be alerted when we first start breaching the threshold, and the impact on customers is still low.
I would expect that when it starts happening again,
we'll see it occur at the top of the hour, perhaps only a couple of times a day at peak.
Once there's the slightest pattern to occurrences,
it's time to make configuration changes, namely to bump MaxStartups in our SSH config.
In `k8s-workloads/gitlab-com`,
in [`releases/gitlab/values/values.yaml.gotmpl`](https://gitlab.com/gitlab-com/gl-infra/k8s-workloads/gitlab-com/-/blob/master/releases/gitlab/values/values.yaml.gotmpl),
adjust the `gitlab.gitlab-shell.config.maxStartups` settings. The `start` and `full` numbers need to increase:

- `start` is the level at which we start dropping pre-auth connections, and this is what we suspect is being hit.
- `full` is the level at which all new pre-auth connections get dropped, so that needs to be some amount bigger than the first;
   we've used +50 so far, and that's probably sufficient.  Our goal here is to not be too brutal to connections too quickly.
- `rate` is what random percentage of connections should be dropped between the first and second limit; 30% is ok,
   you can leave this alone.  Our goal is to not drop *any* connections,
   so this value ideally doesn't make a lot of difference (other than to trigger the first of the drops that we are alerting on here).

At this writing, the values are `250:30:300`;
the lower number was determined by trial and error (see the [issue](https://gitlab.com/gitlab-com/gl-infra/reliability/-/issues/7168)
where this was done), increasing it to a point where errors were eliminated.
Sadly (as noted above) at this time there is no way to see how close we are to hitting this limit before the fact,
meaning reducing again in future is risky.
This implies that until we gain such observability,
we should not increase this by large increments (e.g. I would suggest < 50% increase at any one incident)

Commit, push, merge, and apply the Helm chart.

**Limits:** We don't know, but the only known direct impact of increasing this number is some (fairly small)
memory usage in the ssh server for holding early stage connections;
the defaults were `10:30:100`, and we're well above that without anything really noticing negative effects.
Obviously larger numbers (tens-to-hundreds of thousands) might be interesting
in terms of TCP handling, but I don't expect we'll get there.
Instinctively I'd be a bit wary of it getting above 1000, but if you can observe and measure that it's ok, go nuts.
The higher this value is, the more connections our git servers will then be expected to handle concurrently
when the connection finishes auth, and authentication requires an API call and DB operations,
so keep an eye on CPU and load on the git server before and after any bumps.
If it's getting out of hand, more git servers are likely required,
which will implicitly reduce the number of connections that each server will be handling.

## Additional Context

This is a twitchy/aggressive alert (low threshold, short period), because the issue we're trying to detect is very short and spiky,
but also because it absolutely should not occur under normal circumstances, and we have sufficient levers to pull to control it.
The most obvious is MaxStartups (see above), although we can also adjust `rate-limit sessions` in `roles/gprd-base-haproxy-main.json` down,
to control the number of connections being dispatched to SSH per second.
See <https://gitlab.com/gitlab-com/gl-infra/reliability/-/issues/7168#note_191678023>
and <https://gitlab.com/gitlab-com/gl-infra/reliability/-/issues/7168#note_193486226>
for discussion of the math of this.  However, lowering this too far will affect the user experience negatively,
and MaxStartups is a much cheaper and safer level to pull (increase).

The metric for this alert comes from mtail on HAProxy nodes, and counts 'termination_state' of 'SD' and bytes_read of `0` bytes
on SSH connections (to the git front-end servers), which is a good surrogate indicator for MaxStartups being breached.
