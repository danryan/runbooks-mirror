# PubSub Queuing Rate Increasing

## Reason

* PubSub takes our log messages from fluentd and sends them to PubSub, which is
  later subscribed to by our pubsubbeat machines that forward the logs to
  Elasticsearch.
* Either the beats, or elasticsearch itself, is having issues ingesting /
  forwarding these logs.

## Prechecks

* This [dashboard](https://dashboards.gitlab.net/d/USVj3qHmk/logging)
  will provide details on the status of our pubsubs
  * If the queues for the following are growing, continue to investigate:
    * Backlog size
    * Old unacknowledged message age
    * unacknowledged messages
    * Rate of change of unacked messages (there is a panel for this). If it's
      positive and flat, ingestion has likely stopped altogether.

## Resolution
* If `Publish message operations` has a spike, ensure it goes back down.
  * Ask around for potential changes to any characteristics of our
    infrastructure or application logging
* If the queues continue to climb, check the health of the elastic cluster
  * https://cloud.elastic.co/region/gcp-us-central1/deployment/022d92a4ba7ff6fdacc2a7182948cb0a/elasticsearch
    * Ensure we have enough space in disk usage, and ensure we aren't toppling
      memory usage
    * [Performance Charts](https://cloud.elastic.co/region/gcp-us-central1/deployment/022d92a4ba7ff6fdacc2a7182948cb0a/metrics)
    * Check the status of snapshots, sometimes those go upside down and take too
      long
    * If anything looks wrong here, open a support request
* As one resort, we can halt a particular queue with the hope that we'll
  eventually catch up
  * For every topic, exists a server
  * `knife node list | grep pubsub`
  * ssh into the chosen server, stop the pubsubbeat service
  * This will only stop that one topic, but messages will continue to gather in
    pubsub
* You can try to lower the retention on ES
  * Make your change in [esc-tools cleanup script](https://ops.gitlab.net/gitlab-com/gl-infra/gitlab-restore/esc-tools/blob/master/cleanup_indices.sh)
  * Run the `Daily cleanup` schedule manually [here](https://ops.gitlab.net/gitlab-com/gl-infra/gitlab-restore/esc-tools/pipeline_schedules)
* Should there be unallocated shards
  * Use `debug_allocation.sh` in [the esc-tools repo](https://ops.gitlab.net/gitlab-com/gl-infra/gitlab-restore/esc-tools/tree/master) to find out why.
* As yet another resort, we could consider acking all messages in pubsub
  * This will induce data loss, so this would only be recommended as a final
    resort, and for queues in which we are okay with losing said data
  * Example command for execution:
```
gcloud alpha pubsub subscriptions seek <subscription path> --time=yyyy-mm-ddThh:mm:ss
```

## Postchecks
* Check our stackdriver chart and ensure we don't have things queued.
