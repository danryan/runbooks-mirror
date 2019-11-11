## Steps to check

1. Login to server - `prometheus.gitlab.com` or `prometheus-2.gitlab.com`. Check service with `sv status prometheus`. If it is `run` for more than `0s`. Then it is ok.
1. If it is `down` state, then check logs in `/var/log/prometheus/prometheus/current`. Actions can be taken after logs investigating. Usually it is configuration error or IO/space problems.

## How to work with Prometheus

1. Check configuration - `/opt/prometheus/prometheus/promtool check config /opt/prometheus/prometheus/prometheus.yml`.
It should check prometheus configuration file and alerts being used. Please always run this check before restarting prometheus service.
1. Reload configuration - `sudo sv reload prometheus`.
1. Restart service - `sudo sv restart prometheus` after checking configuration.

## Many Restarts

### thanos-compact

Sometimes the chunks of data in GCS that thanos-compact is working on can be corrupted in ways that cause thanos-compact to crash hard and restart, leading to a crashloop and the PrometheusManyRestarts alert.

One such issue resulted in this log:
```
{"caller":"main.go:215","err":"error executing compaction: compaction failed: compaction failed for group 0@{env=\"gprd\",monitor=\"app\",provider=\"gcp\",region=\"us-east\",replica=\"02\"}: compact blocks [/opt/prometheus/thanos/compact-data/compact/0@{env=\"gprd\",monitor=\"app\",provider=\"gcp\",region=\"us-east\",replica=\"02\"}/01DS5AQG40F0NWX3GP57KR1XGF /opt/prometheus/thanos/compact-data/compact/0@{env=\"gprd\",monitor=\"app\",provider=\"gcp\",region=\"us-east\",replica=\"02\"}/01DS5HK7C0HR5WNS9KHEXV0J68 /opt/prometheus/thanos/compact-data/compact/0@{env=\"gprd\",monitor=\"app\",provider=\"gcp\",region=\"us-east\",replica=\"02\"}/01DS5REYM1E1J0X3GTVZ9NNJ68 /opt/prometheus/thanos/compact-data/compact/0@{env=\"gprd\",monitor=\"app\",provider=\"gcp\",region=\"us-east\",replica=\"02\"}/01DS5ZANVZ9N7A14EKPHPZ70MM]: write compaction: iterate compaction set: chunk 45 not found: invalid encoding \"\u003cunknown\u003e\"","level":"error","msg":"running command failed","ts":"2019-11-11T04:12:56.374664759Z"}
```

The key identifier is "compaction failed for group".
The rest of the message is a bit hard to read, but the interesting facts are
1. the identifier of the source: "0@{env=\"gprd\",monitor=\"app\",provider=\"gcp\",region=\"us-east\",replica=\"02\"}", which says that this came from prometheus-app-02-inf-gprd ('env', 'monitor', and 'replica' are the relevant parts).  This is possibly only tangentially interesting, for locating the source of the corruption 
1. The chunk names.  In the above example, these are 01DS5AQG40F0NWX3GP57KR1XGF, 01DS5HK7C0HR5WNS9KHEXV0J68, 01DS5REYM1E1J0X3GTVZ9NNJ68 , and 01DS5ZANVZ9N7A14EKPHPZ70MM

In this situation there does not appear to be any reasonable way to recover the data in those chunks, and we should count the data as lost.  Renaming them (e.g. adding a .bak suffix) removes them from visibility to thanos-compact, and allows it to continue with what it can.  Having extracted the $CHUNKX names from the logs, the following will rename them:

```bash
for i in $CHUNK1 $CHUNK2 $CHUNK3 $CHUNK4; do gsutil mv gs://gitlab-gprd-prometheus/$i gs://gitlab-gprd-prometheus/$i.bak; done
```

Adjust the `gprd` component of the bucket name based on which environment you're working on.  This keeps the broken chunks around in case someone wants to debug the corruption.  They could likely be deleted as well, if there's no such desire, but renaming is the less intrusive option.

You may have to do this multiple times as it finds new corrupted chunks; keep a tail on the logs until the restarts cease.
