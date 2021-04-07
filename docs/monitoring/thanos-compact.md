# Thanos Compact

[[_TOC_]]

Thanos compact failures are almost always discoverable in the logs.

In GCE: `journalctl -eu thanos-compact`

Note that due to cross-environment monitoring, the env of the alert may not
correspond to the environment whose thanos-compact singleton is broken. Pay
close attention to the alert's metadata to determine where to look.

## Common problems

* OOMs, check for crashes in the logs or non-zero `node_vmstat_oom_kill` .
* Storage, Large compactions may trigger a full filesystem. Restart of `thanos-compact` will clear the compaction cache.
* Halted compaction (ThanosCompactHalted alerts). See various scenarios below.

### Overlapping TSDB blocks

If you see log lines similar to this:

```
Oct 19 11:11:37 thanos-compact-01-inf-gprd thanos[16770]: {"caller":"compact.go:377","err":"compaction: group 0@4648145191823988568: pre compaction overlap check: overlaps found while gathering blocks. [mint: 1601467200000, maxt: 1601474400000, range: 2h0m0s, blocks: 2]: <ulid: 01EKFZS4BHWGDNP0ZB7FEHFVYM, mint: 1601467200000, maxt: 1601474400000, range: 2h0m0s>, <ulid: 01EKFRDZCR4HEZNWQG8Z2RZ22Y, mint: 1601467200000, maxt: 1601474400000, range: 2h0m0s>","level":"error","msg":"critical error detected; halting","ts":"2020-10-19T11:11:37.338106404Z"}
```

Then thanos-compact is complaining that 2 or more TSDB blocks in the metrics
bucket have overlapping time periods.

For each set of overlapping blocks, pull down the metadata corresponding to
their ULIDs:

```
for block in 01EKFZS4BHWGDNP0ZB7FEHFVYM 01EKFRDZCR4HEZNWQG8Z2RZ22Y; do
  gsutil cp gs://gitlab-gprd-prometheus/$block/meta.json ./$block.meta.json
done
```

Examine the metedata files. They should look similar to this:

```
{
  "ulid": "01EKFRDZCR4HEZNWQG8Z2RZ22Y",
  "minTime": 1601467200000,
  "maxTime": 1601474400000,
  "stats": {
    "numSamples": 415715189,
    "numSeries": 3257866,
    "numChunks": 3356768
  },
  "compaction": {
    "level": 1,
    "sources": [
      "01EKFRDZCR4HEZNWQG8Z2RZ22Y"
    ]
  },
  "version": 1,
  "thanos": {
    "labels": {
      "cluster": "gprd-gitlab-gke",
      "env": "gprd",
      "environment": "gprd",
      "monitor": "default",
      "prometheus": "monitoring/gitlab-monitoring-promethe-prometheus",
      "prometheus_replica": "prometheus-gitlab-monitoring-promethe-prometheus-1",
      "provider": "gcp",
      "region": "us-east1"
    },
    "downsample": {
      "resolution": 0
    },
    "source": "sidecar"
  }
}
```

We have observed 2 scenarios, with different solutions: totally overlapping
blocks, and partially overlapping blocks. Note the time range, between the
timestamps minTime and maxTime, and follow one of the scenarios below.

#### Partially overlapping blocks

We have observed this scenario less often, and are not yet sure why it occurs.
When it has occurred, it has been for compact-sourced (as opposed to
sidecar-sourced) blocks with level > 1.

The current mitigation is to mark all blocks involved as "no-compact":

```
export GOOGLE_APPLICATION_CREDENTIALS=/opt/prometheus/thanos/gcs-creds.json
block_list='01EJQ1JVX2RYAVAVBC1CJCESJD 01EJR6MVVKPKQ781VFYKHSH5Z0 01EJXNXJ9NRKESZ7GQT6JXZNNW 01EK36WZ2W5HJKXC1D7S8HFY4H 01ERY52QYS0TXXSRAP14N6NJH5'
for id in ${block_list} ; do
  /opt/prometheus/thanos/thanos tools bucket mark \
    --objstore.config-file=/opt/prometheus/thanos/objstore.yml \
    --marker=no-compact-mark.json \
    --details='ISSUE LINK HERE' \
    --id="${id}"
done
```

Then restart thanos-compact.

#### Totally overlapping blocks

We're not 100% sure why this happens, but we suspect it could be due to a race
condition that is most likely to be teased out when prometheus pods are
restarting frequently. The prometheus process will attempt to recover from WAL
on the persistent volume, writing out a TSDB segment. The thanos-sidecar process
will then try to upload these TSDB segments. If Prometheus crashes without
completing the WAL replay, it may not know that the TSDB block write was
successful. It then attempts to create the same block a second time.

We have only observed this problem for sidecar-uploaded "raw" blocks, not ones
that have already been compacted by thanos-query:

* compaction.level == 1
* compaction.sources is a single-element array, and the value of that element is
  equal to ulid.
* downsample.resolution == 0
* source == "sidecar"

Select the block with the highest value of numSamples. This is the one we'll be
keeping.

For each other block, move it to a pathname that thanos will not care about:

```
gsutil -m mv gs://gitlab-gprd-prometheus/ULID gs://gitlab-gprd-prometheus/backup-YYYY-MM-DD/ULID
```

Then, restart thanos-compact. While we're still running this in GCE: `systemctl
restart thanos-compact`. This will likely hang on shutdown. If you don't want to
wait for the systemd timeout, `kill -9` the process.

Validate that the alert has resolved. thanos-compact should be able to process
the section it was previously failing on - but it's possible that there are more
duplicates ahead, which will cause the alert to re-fire. Pay attention to
[`thanos_compactor_halted`](https://thanos.gitlab.net/graph?g0.range_input=12h&g0.max_source_resolution=0s&g0.expr=thanos_compactor_halted%7Benv%3D%22gprd%22%7D&g0.tab=0).

### Compacted indexes too large

Thanos / Prometheus has a maximum index size of 64GB. As thanos compacts
segments together, it tries to avoid creating new indexes larger than this size,
by skipping compaction of such blocks. Sometimes, this doesn't work
(https://github.com/thanos-io/thanos/issues/3724).

#### Symptoms

- Thanos compaction halted (`thanos_compact_halted == 1`).
- `level: error` messages in the logs, with content "compact blocks... exceeding max size of 64GiB"

At the time compaction halted, you should see a message of the form:

```
{"caller":"compact.go:428","err":"compaction: group 300000@4648145191823988568: compact blocks
[
/opt/prometheus/thanos/compact-data/compact/300000@4648145191823988568/01EJQ1JVX2RYAVAVBC1CJCESJD
/opt/prometheus/thanos/compact-data/compact/300000@4648145191823988568/01EJR6MVVKPKQ781VFYKHSH5Z0
/opt/prometheus/thanos/compact-data/compact/300000@4648145191823988568/01EJXNXJ9NRKESZ7GQT6JXZNNW
/opt/prometheus/thanos/compact-data/compact/300000@4648145191823988568/01EK36WZ2W5HJKXC1D7S8HFY4H
/opt/prometheus/thanos/compact-data/compact/300000@4648145191823988568/01ERY52QYS0TXXSRAP14N6NJH5
]:
\"/opt/prometheus/thanos/compact-data/compact/300000@4648145191823988568/01EVVZNNZ7KJ53PDN96EVQEA6A.tmp-for-creation/index\" exceeding max size of 64GiB",
"level":"error","msg":"critical error detected; halting","ts":"2021-01-13T02:00:08.556808522Z"}
```

#### Resolution

Use thanos tools from a shell in the compactor's environment to mark these
blocks for skipping. In our GCE infrastructure, this looks like:

```
export GOOGLE_APPLICATION_CREDENTIALS=/opt/prometheus/thanos/gcs-creds.json
block_list='01EJQ1JVX2RYAVAVBC1CJCESJD 01EJR6MVVKPKQ781VFYKHSH5Z0 01EJXNXJ9NRKESZ7GQT6JXZNNW 01EK36WZ2W5HJKXC1D7S8HFY4H 01ERY52QYS0TXXSRAP14N6NJH5'
for id in ${block_list} ; do
  /opt/prometheus/thanos/thanos tools bucket mark \
    --objstore.config-file=/opt/prometheus/thanos/objstore.yml \
    --marker=no-compact-mark.json \
    --details='ISSUE LINK HERE' \
    --id="${id}"
done
```

We will need a similar process in place when we move thanos-compact to
Kubernetes. In principle you can do this with local thanos binary against the
bucket from your workstation, but `kubectl exec` will likely be the preferred
procedure.

Restart thanos-compact.

#### Example incidents

- https://gitlab.com/gitlab-com/gl-infra/production/-/issues/3308
