# [SnowPlow](https://github.com/snowplow/snowplow/wiki/snowplow-tracker-protocol)

**Table of Contents**

[TOC]

SnowPlow is a pipeline of nodes and streams that is used to accept events from the GitLab.com and other applications. Snowplow SDK is used to instrument the events from these various applications to the Snowplow endpoint.

All of the SnowPlow pipeline components live in AWS GPRD account: `855262394183`.

* [Design Document](https://about.gitlab.com/handbook/engineering/infrastructure/design/snowplow/)
* [Terraform Configuration](https://ops.gitlab.net/gitlab-com/gitlab-com-infrastructure/tree/master/environments/aws-snowplow)
* Cloudwatch [aws-snowplow](https://us-east-2.console.aws.amazon.com/cloudwatch/home?region=us-east-2#dashboards/dashboard/SnowPlow) and [aws-snowplow-prd](https://us-east-2.console.aws.amazon.com/cloudwatch/home?region=us-east-2#dashboards/dashboard/aws_snowplow_prd)

## The Pipeline Diagram

![SnowPlow Diagram](../img/snowplow/snowplowdiagram.png "SnowPlow Diagram")

## Action steps on Incident

1. Create an incident in Slack, [handbook instructions](https://handbook.gitlab.com/handbook/engineering/infrastructure/incident-management/#report-an-incident-via-slack)
    * The incident should be labelled **P3**, as this is internal-only.
1. Read through the runbook, the 'What is important' section may be a good place to start

## Past Incident list

Incident list starting in December, 2024. This list is not guaranteed to be complete, but could be useful to reference for future incidents:

1. 2024-12-01: [Investigate why snowplow good events backing up takes time](https://gitlab.com/gitlab-org/gitlab/-/issues/507248#note_2241426826)
1. [2024-12-10: Snowplow enriched events are not getting processed](https://gitlab.com/gitlab-com/gl-infra/production/-/issues/18975#note_2251924192)

## Note: Interim transition period

As of October, 2024-Q3, we are in an interim period of 6 months where we will be maintaining **two** production environments. In config-mgmt, these environments are called:

* `aws-snowplow`, infra hosted in `us-east-1`
* `aws-snowplow-prd`, infra hosted in `us-east-2`

Over these 6 months, traffic for various Snowplow applications will be shifted from using the former environment for the latter environment, the rollout plan is captured in [this issue](https://gitlab.com/gitlab-org/architecture/gitlab-data-analytics/design-doc/-/issues/77#note_2154946117).

You may need to check one or the other environment, based on the Snowplow application (i.e gitlab.com vs switchboard) in question and the current status of the rollout plan. For example, if there are problems with events for gitlab.com application, and we're still in Phase 1 of the rollout to the new environment, that means that the problem would be in the older environment `aws-snowplow`.

To update the appropriate environment, go to `us-east-1` for `aws-snowplow` environment, and go to `us-east-2` for `aws-snowplow-prd` environment.

## What is important?

If you are reading this, most likely one of two things has gone wrong. Either the SnowPlow pipeline has stopped accepting events or it has stopped writing events to the S3 bucket. Not accepting requests is a big problem and it should be fixed as soon as possible. Collecting events is important and a synchronous process.

Processing events and writing them out is important, but not as time-sensitive.  There is some slack in the queue to allow events to stack up before being written.

The raw events Kinesis stream has a data retention period of 48 hours. This can be altered if needed in a dire situation [aws-snowplow-prd/main.tf](https://ops.gitlab.net/gitlab-com/gl-infra/config-mgmt/-/blob/main/environments/aws-snowplow-prd/main.tf?ref_type=heads), and searching for `retention_period` argument.

## Not accepting requests

1. A quick curl check should give you a good response of **OK**. This same URL is used for individual collector nodes to check health against port 8000:
    * `curl` the snowplow endpoint:
        * aws-snowplow env: `curl https://snowplow.trx.gitlab.net/health`
        * aws-snowplow-prd env: `curl https://snowplowprd.trx.gitlab.net/health`
1. Log into GPRD AWS and verify that there are collector nodes in the
  `SnowPlowNLBTargetGroup` EC2 auto-scaling target group. If not, something has gone wrong
  with the snowplow PRD collector Auto Scaling group.
1. Check `Cloudflare` and verify that the DNS name is still
  pointing to the EC2 SnowPlow load balancer DNS name. The record in Cloudflare should be a `CNAME`.
    * aws-snowplow env, DNS name: `snowplow.trx.gitlab.net`
    * aws-snowplow-prd env, DNS name: `snowplowprd.trx.gitlab.net`
1. If there are EC2 `collectors` running, you can SSH (see 'how to SSH section') into the instance and then check the logs by running:

    ```sh
    docker logs --tail 15 stream-collector
    ```

3. Are the collectors writing events to the raw (good or bad) Kinesis streams?
    * You can look at the [aws-snowplow](https://us-east-2.console.aws.amazon.com/cloudwatch/home?region=us-east-2#dashboards/dashboard/SnowPlow) or [aws-snowplow-prd](https://us-east-2.console.aws.amazon.com/cloudwatch/home?region=us-east-2#dashboards/dashboard/aws_snowplow_prd) `Cloudwatch` dashboard, or go to the `Kinesis Data streams` service in AWS and look at the stream monitoring tabs.

## Not writing events out

1. First, make sure the collectors are working ok by looking over the steps above. It's possible that if nothing is getting collected, nothing is being written out.
1. In the [aws-snowplow](https://us-east-2.console.aws.amazon.com/cloudwatch/home?region=us-east-2#dashboards/dashboard/SnowPlow) or [aws-snowplow-prd](https://us-east-2.console.aws.amazon.com/cloudwatch/home?region=us-east-2#dashboards/dashboard/aws_snowplow_prd) Cloudwatch dashboard, look at the **Stream Records Age** graph to see if a Kinesis stream is backing up. This graph shows the milliseconds that records are left in the streams and it should be zero most of the time. If there are lots of records backing up, the enrichers may not be picking up work, or Firehose is not writing records to S3. Reference the pipeline diagram above to help determine which broken part might cause a stream to have long-lived records in the stream.
1. Verify there are running enricher instances by checking the
  `SnowPlowEnricher` auto scaling group.
1. There is no current automated method to see if the enricher processes are running on the nodes. To check the logs, SSH (see 'how to SSH section') into one of the enricher instances and then run:

    ```sh
    docker logs --tail 15 stream-enrich
    ```

1. Are the enricher nodes picking up events and writing them into the enriched Kinesis streams? Look for the `Kinesis stream monitoring` tabs.
1. Check that the `Kinesis Firehose` monitoring for the enriched (good and bad) streams are processing events. You may want to turn on CloudWatch logging if you are stuck and can't seem to figure out what's wrong.
1. Check the `Lambda` function that is used to process events in Firehose. There should be plenty of invocations at any time of day. A graph of invocations is also in Cloudwatch.

## Key Cloudwatch Dashboards

Cloudwatch [aws-snowplow](https://us-east-2.console.aws.amazon.com/cloudwatch/home?region=us-east-2#dashboards/dashboard/SnowPlow) and [aws-snowplow-prd](https://us-east-2.console.aws.amazon.com/cloudwatch/home?region=us-east-2#dashboards/dashboard/aws_snowplow_prd) dashboards tracking each environment.

In the past, the two most important dashboards have been:

1. `stream records age`: the most important because it measures how long events are sitting in Kinesis (which means they’re not getting enriched, in the past we have had problem with it backing up)
1. `Auto-scaling group size`: if we see collectors scaling up, but not scaling back down, we may need to increase the number of collectors to make sure we’re always ready to ingest bigger event traffic

## Updating enricher config

The Snowplow collector and enricher instances are started with launch configuration templates.
These launch configuration templates include the Snowplow configs- `collector-user-data.sh` and `enricher-user-data.sh`.

The Snowplow configs are used to configure how the Snowplow collector/enricher and the Kinesis stream interact, and may occasionally need to be updated, here are the steps:

1. Within the .sh file(s), update the Snowplow config values
1. Create an MR to apply the changes, which should update the aws_launch_configuration resource, [example MR](https://ops.gitlab.net/gitlab-com/gl-infra/config-mgmt/-/merge_requests/9788)

In the `aws-snowplow` environment *only*, you need to manually force an instance refresh in order for the instances to use the new config. To do the instance refresh, see the 'Refreshing EC2 instances within auto-scaling group' section.

In the `aws-snwowplow-stg/prd` environments, this isn't necessary because the terraform configures a `rolling update`.

Lastly, to check that your config has been updated, ssh into one of the instances (see ssh section) and run:

```sh
cat /snowplow/config/config.hocon
```

## EC2 instance refresh

You may need to do a instance refresh manually, for example because:

* instances have become unresponsive
* you've updated the launch config in the `aws-snowplow` env

Here are the instructions:

1. The instances need to be terminated/recreated for them to use the updated config. To access the `instance_refresh` tab in the UI:
    * go to EC2 -> Auto Scaling groups -> click 'snowplow PRD enricher' or 'snowplow PRD collector' -> Instance refresh
1. Once in the 'Instance refresh' tab, click 'Start instance refresh'
1. For settings, use:
    * Terminate and launch (default already)
    * Set healthy percentage, Min=`95%`
    * the rest of the settings, you can leave as is
1. Click 'Start instance refresh', and track its progress

## A note on burstable machines

Currently, the EC2 collector/enricher instances both use the `t` [machine types](https://aws.amazon.com/ec2/instance-types/).

These machine types are [burstable](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/burstable-performance-instances.html):

> The T instance family provides a baseline CPU performance with the ability to burst above the baseline at any time for as long as required

When the instances are bursting, they consume CPU credits.

If the CPU usage is especially high, it may not be apparent at first, because the machines are bursting.
But once all CPU credits have been consumed the machines can no longer burst, and this could lead to degradation of the system, as seen in the `2024-12-10` incident.

As such, it's important to do the following:

* be aware that we are using burstable instances
* keep an eye on the CPU credits, which can be seen in the EC2 UI for a specific instance. This is an important point especially during big changes such as upgrades, as seen in the `2024-12-10` incident.

## How to SSH into EC2 instances

There are 2 ways to SSH into EC2 instance:

1. Using `EC2 Instance Connect` (AWS UI):
    * Login to AWS and go to [EC2 Instances](https://us-east-2.console.aws.amazon.com/ec2/home?region=us-east-2#Instances:)
    * click the `instance_id` that you want to enter, then click the 'Connect' tab
    * Select `Connect using EC2 Instance Connect` (it should be selected by default), and then click 'Connect'
1. From bastion host:
    * you will need the `snowplow.pem` file from 1Password Production Vault and you will connect to the nodes as the `ec2-user`. Your command should look something like this:

        ```sh
        ssh -i "snowplow.pem"  ec2-user@<ec2-ip-address>
        ```
