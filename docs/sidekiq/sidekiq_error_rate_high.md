## Symptoms

**Table of Contents**

[TOC]

* An alert in `#alerts-general` for Sidekiq's error ratio exceeding SLO

## Troubleshooting

* It's important to mind which sidekiq job is having issues. This
  [chart](https://log.gprd.gitlab.net/app/kibana#/visualize/edit/AW3J3Lc4zkPhEGn_VsuR)
  shows the worker classes with the most errors. You might want to drill down
  [to service class](https://log.gprd.gitlab.net/app/kibana#/visualize/edit/AW2moVRdUOguGaJ_mRPG).
* For most of them, ideally we'd contact the #backend and ask for insight
* Some we can potentially troubleshoot ourselves

### ReactiveCachingWorker

* This one likes to fire when end users might have misconfigured an integration
  with their project.
  * As a quick example, if they utilize the Bamboo CI Integration, they are
    required to input a server fqdn.  Should this be incorrect, or if their
    Bamboo server is down, the integration might fail.
* The next best step is to check <https://sentry.gitlab.net> for errors
  * Perform a search for `ReactiveCachingWorker` and see if there might be any
    recent errors
* Following the example above, we might see an error such as this:

```
Errno::EHOSTUNREACHSidekiq/ReactiveCachingWorker
Failed to open TCP connection to 192.0.2.188:8089 (No route to host -connect(2)...
```

* In this case we can quickly discern that some integration is not successfully
  connecting to this IP address
  * Browse into that error
  * In the "additional data", subsection "sidekiq", you'll find something
    similar to this:

```
{
context: Job raised exception,
job: {
args: [
BambooService,
40888973,
41af8888732fd99c7a69cd5dbc230174ec538f36,
development
],
```

* In this example we can confirm there's trouble using the Bamboo CI Integration
  from project id `40888973`
* In this case, we'll use our administrative power to disable this integration
* First find the project:
  * Log into a rails console
  * `BambooService.find(40888973).project` will return the project
* Now disable the integration
  * Using your administrative rights, log into gitlab, navigate to the project
  * Go to the integrations section
  * Find, in this example, Bamboo CI
  * Browse into it's configuration, Disable and save it
* Finally, reach out to support letting them know your findings, the decision
  into what led disabling this integration, and ask that they reach out to the
  end user

### GithubService (ProjectServiceWorker)

Until <https://gitlab.com/gitlab-org/gitlab/issues/30996> is fixed, client errors
are reported as job errors from this service. If the logs are full of 4XX
errors, there is nothing to do. We can't stop users from submitting incorrect
repo paths or invalid credentials.
