# Rails middleware: path traversal

[[_TOC_]]

This runbook covers the operations of the [rails middleware path traversal](https://gitlab.com/gitlab-org/gitlab/-/blob/master/lib/gitlab/middleware/path_traversal_check.rb).

## Overview

The main idea behind the middleware is to run a [path traversal guard function](https://gitlab.com/gitlab-org/gitlab/-/blob/13bd92ac334c714318ba507efcca8b007d3e90ff/lib/gitlab/path_traversal.rb#L35) on the accessed path for web requests.
It will also take into account encoded characters (`%2F` for `/`) and the query parameters value (for example: `/foo?parameter=value`).
Nested parameters(`/foo?param[test]=bar`) are also checked up to a depth level of `5`.

Since this is a Rails middleware, the backend will:

* execute this for _all_ web requests.
* execute this pretty early in the request processing (before the Rails router and several other middlewares).

If a path traversal is detected,

* the request processing is interrupted and a `400 Bad Request` response with the body `Potential path traversal attempt detected.`.
* the attempt is logged.

### Controlling the behavior

The middleware is currently controlled by two feature flags:

* `check_path_traversal_middleware`. This is the main switch. Disabling this will entirely disable the middleware and make it a no-op.
* `check_path_traversal_middleware_reject_requests`. This flag controls if we reject the request in case of an attempt. The attempt is logged no matter the state of this flag.

## Dashboards & Logs

In case of an incident with this middleware, look at:

* The two `Middleware check path traversal *` dashboards in the `Rails` components panel for the current performance. It is available in the [web: Overview](https://dashboards.gitlab.net/d/web-main/web-overview?orgId=1).
  * The first dashboard will show the executions rate.
  * The second dashboard is an Apdex chart on the execution time with a threshold of `1 ms`.
  * Each dashboard will show two lines: one for rejected request and one for accepted requests.
* [Kibana logs](https://log.gprd.gitlab.net/app/r/s/8bYSz) for a detailed report on requests detected as attempts.

## Failures

### Rejecting requests that should be accepted

The `Middleware check path traversal executions rate` chart will show an increasing rate for rejected requests.

* Check the [Kibana logs](https://log.gprd.gitlab.net/app/r/s/8bYSz) and investigate the paths of the request that are rejected.
  * If these are genuine path traversal attempts, then we might be the target of an automated script that tries different urls with path traversal in bulks.
    * Dig in of these request come from the same source or not.
  * If these are valid requests that should be accepted, reach out the owning team to fill a bug issue.

### Longer execution time

In this case, the `Middleware check path traversal execution time Apdex` chart should show low numbers.
This is a clear indication that the middleware is taking too much time to run the path traversal regexp.

This should be a symptom of a root cause external to the middleware.
