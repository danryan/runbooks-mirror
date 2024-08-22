# GitLab Job Completion

> This page is about monitoring & alerting on job completion (i.e., jobs that trigger but fail to complete within the expected time, or complete over the expected time). For alerting on jobs that fail to trigger, see [periodic job monitoring](./periodic_job_monitoring.md).

[[_TOC_]]

## Purpose and implementation

The main purpose of a job completion metric is to observe if a given task or action has successfully run in the required interval. This can be used in various scenarios, where active monitoring is not applicable, such as cron jobs, or scheduled pipeline executions. If these were to fail to check back in the targeted interval, an alert would fire informing about this incident.

This is implementated via Prometheus Pushgateway. To register and check-in a successful execution, the cron/pipeline publish the required metrics to a Pushgateway. See below for details. Should the time difference be greater than the defined time it would trigger the alert.

## Creating and updating a new job metric

Creating a new job completion metric is the same process as checking-in/updating. This is driven by convention over configuration. It is enough to publish a metric with an arbitrary `resource` label, specifying the resource that the alert reports on. This could be a URL to a repository and the job name in case of a scheduled pipeline, but must not include data, that changes between invocations (e.g. pipeline or job IDs). In addition to that the `type` and `tier` labels are required, as per all our alerts. These should correspond with the type and tier of the underlying service, that the deadman switch is monitoring.

Three metrics are required:

| Metric                                  | Description  |
| --------------------------------------- | ------------ |
| `gitlab_job_max_age_seconds`            | This is the allowed age before the alert should fire, in seconds. |
| `gitlab_job_start_timestamp_seconds`    | This is the unix time in seconds when the job starts.  |
| `gitlab_job_success_timestamp_seconds`  | This is the unix time in seconds when the job completes succesfully. It should be set to 0 at job start. |
| `gitlab_job_failed`                     | This is a boolean value of the job completion status. |

The below code can be used within a bash script (after having exported the respective environment variables)

`report_start.sh`:

```bash
cat <<PROM | curl -iv --data-binary @- "http://${PUSH_GATEWAY}:9091/metrics/job/${JOB}/tier/${TIER}/type/${TYPE}"
# HELP gitlab_job_start_timestamp_seconds The start time of the job.
# TYPE gitlab_job_start_timestamp_seconds gauge
gitlab_job_start_timestamp_seconds{resource="${RESOURCE}"} $(date +%s)
# HELP gitlab_job_success_timestamp_seconds The time the job succeeded.
# TYPE gitlab_job_success_timestamp_seconds gauge
gitlab_job_success_timestamp_seconds{resource="${RESOURCE}"} 0
# HELP gitlab_job_max_age_seconds How long the job is allowed to run before marking it failed.
# TYPE gitlab_job_max_age_seconds gauge
gitlab_job_max_age_seconds{resource="${RESOURCE}"} ${MAX_AGE}
# HELP gitlab_job_failed Boolean status of the job.
# TYPE gitlab_job_failed gauge
gitlab_job_failed{resource="${RESOURCE}"} 0
PROM
```

`report_success.sh`:

```bash
cat <<PROM | curl -iv --data-binary @- "http://${PUSH_GATEWAY}:9091/metrics/job/${JOB}/tier/${TIER}/type/${TYPE}"
# HELP gitlab_job_success_timestamp_seconds The time the job succeeded.
# TYPE gitlab_job_success_timestamp_seconds gauge
gitlab_job_success_timestamp_seconds{resource="${RESOURCE}"} $(date +%s)
PROM
```

`report_failed.sh`:

```bash
cat <<PROM | curl -iv --data-binary @- "http://${PUSH_GATEWAY}:9091/metrics/job/${JOB}/tier/${TIER}/type/${TYPE}"
# HELP gitlab_job_failed Boolean status of the job.
# TYPE gitlab_job_failed gauge
gitlab_job_failed{resource="${RESOURCE}"} 1
PROM
```

| Variable | Description |
| -------- | ----------- |
| `PUSH_GATEWAY` | The hostname/IP of the pushgateway to push to (check firewalls, stay within environment if possible) |
| `MAX_AGE` | The SLO value for alerting, in seconds. |
| `RESOURCE` | The resource identifier to include in alerts (e.g. `assign_weights`). Do not include data, that changes between invocations (such as pipeline or job IDs for example) |
| `TIER` | The tier of the monitored service (e.g. `db`) |
| `TYPE` | The tpye of the monitored service (e.g. `postgres`) |

### Job metric per env or per node

For tracking a job that is expected to succeed on each node use `localhost` as
`$PUSH_GATEWAY`.

If you have a job that should only run on one random node in an env each time
(e.g. the wal-g backup job), then use a central pushgateway to avoid having
metrics labeled with different fqdn and thus getting alerts if the job didn't
happen to run on the same node for a while. For gstg, gprd and ops you can use
the blackbox nodes as central pushgateway.

## Removing Job Metrics

To remove metrics from the pushgateway check [how to delete metrics](../monitoring/pushgateway.md#how-to-delete-metrics)

## Alerting

Any metric reporting created like above automatically has alerting enabled. These alerts will be sent out to s4.
