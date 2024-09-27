# Cloudflare Logs

**Table of Contents**

[TOC]

Each CloudFlare zone pushes logs to a Google Cloud Storage (GCS) bucket with
the name of `gitlab-<environment>-cloudflare-logpush`. This operation happens
every 5 minutes so the logs don't give an immediate overview of what's
currently happening.

Starting 2022-04-14 we enabled Logpush v2. These logs will be shipped to a distinct `v2` subdirectory in that GCS bucket.

Logpush v2 allows us to also access logs for Firewall events, DNS and NELs. These are not configured at the moment, but can be enabled if the need arises.

At least READ access to GCS in the `Production` project in GCP is required to be able to view these logs.

NELs are also already available as metrics [here](https://dashboards.gitlab.net/d/sPqgMv9Zk/cloudflare-traffic-overview?orgId=1&refresh=5m)

## BigQuery (to be validated for Logpush v2)

The logs for a particular day can be imported into BigQuery by using the `bq` tool:

```bash
curl -s https://raw.githubusercontent.com/cloudflare/cloudflare-gcp/master/logpush-to-bigquery/schema-http.json | jq '. += [{"name": "RequestHeaders","type": "JSON","mode": "NULLABLE"}, {"name": "ResponseHeaders","type": "JSON","mode": "NULLABLE"}]' > schema-http.json
bq load --project_id gitlab-production --source_format NEWLINE_DELIMITED_JSON cloudflare.logpush_20200610 'gs://gitlab-gprd-cloudflare-logpush/v2/http/20200610/*.log.gz' schema-http.json
```

This will make the logs for that particular day available for querying with SQL
via [the BigQuery
UI](https://console.cloud.google.com/bigquery?project=gitlab-production).

By default, imported tables in the `cloudflare` dataset have a retention of 30
days.

Note that BigQuery does not deduplicate records. So if you want to import a newer set of files, it's recommended to either import only the new files selectively, or to delete the table before importing, via:

```bash
bq ls cloudflare
bq rm cloudflare.logpush_20200610
```

## Processing the raw data

If you want to run more ad-hoc analysis, there is also a script, which allows us
to access a NDJSON stream of logs. This script can be found in
`scripts/cloudflare_logs.sh`. The script is adapted to make use of Logpush v2 data.

The usage of the script should be limited to a console host because of traffic
cost. It will need to read the whole logs for the provided timeframe.

Example:

To get the last 30 minutes of logs up until 2020-04-14T00:00 UTC as a stream,
use

```bash
./cloudflare_logs.sh -e gprd -d 2020-04-14T00:00 -t http -b 30
```

you can then `grep` on that to narrow it down. The use of `jq` on an unfiltered
stream is not recommended, as that significantly increases processing time.

Beware, that this process will take long for large timespans.

Full example to search for logs of a given project which have a 429 response
code:

```bash
./cloudflare_logs.sh -e gprd -d 2020-04-14T00:00 -t http -b 2880 \
  | grep 'api/v4/projects/<PROJECT_ID>' \
  | jq 'select(.EdgeResponseStatus == 429)'
```

Note: Due to the way logs are shipped into GCS, there might be a delay of up
to 10 minutes for logs to be available.

## Spectrum logs

The analytics API for Spectrum apps is very limited so querying the logs via BigQuery is the only way to do detailed analysis of non-HTTP/S traffic passing through a Spectrum app (e.g. SSH traffic).

Run the following commands to create an external table:

```bash
curl -s https://raw.githubusercontent.com/cloudflare/cloudflare-gcp/refs/heads/master/logpush-to-bigquery/schema-spectrum.json > schema-spectrum.json
bq mkdef --source_format=NEWLINE_DELIMITED_JSON "gs://gitlab-gprd-cloudflare-logpush/v2/spectrum/*.log.gz" > tabledef
bq mk --table --external_table_definition=tabledef cloudflare_spectrum_logs.latest schema-spectrum.json
```

Note that this will load all Spectrum logs inside the retention period into the table, as we are limited to using one wildcard pattern in the path. If you're only interested in one day, adjust the URI as necessary.

To query if we've had connections from embargoed countries, you can run:

```sql
SELECT * FROM `gitlab-production.cloudflare_spectrum_logs.latest` where upper(ClientCountry) in ("SY","KP","CU","IR") and Event = 'disconnect'
```

## Cloudflare Audit Logs

Different than traffic logging, Cloudflare audit information provides logs
on changes to the Cloudflare configuration. What account turned off a page
rule, or modified a DNS entry, etc.

* Log into cloudflare.com
* When you see a list of zones to manage, near the top of the page
  select `Audit Logs`

[Cloudflare Article](https://support.cloudflare.com/hc/en-us/articles/115002833612-Understanding-Cloudflare-Audit-Logs)

## Retention

Cloudflare logs will be retained for 91 days via GCS object lifecycle management.
