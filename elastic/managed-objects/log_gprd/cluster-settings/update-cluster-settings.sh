#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
export ES_URL=$ES_LOG_GPRD_URL
source "${SCRIPT_DIR}"/../../lib/update-scripts-functions.sh

# https://www.elastic.co/guide/en/elasticsearch/reference/current/disk-allocator.html
# When reaching the storage low-watermark on a node, shards will be no longer be assigned to that node but if all nodes have reached the low-watermark, the cluster will stop storing any data. As per suggestion from Elastic (https://gitlab.com/gitlab-com/gl-infra/production/issues/616#note_124839760) we should use absolute byte values instead of percentages for setting the watermarks and, given the actual shard sizes, we should leave enough headroom for writing to shards, segment merging and node failure.

# (I believe `gb` means GiB, but can't find a reference.)

curl_data_watermark() {
    cat <<EOF
{
    "persistent": {
        "cluster.routing.allocation.disk.watermark.low": "86%",
        "cluster.routing.allocation.disk.watermark.high": "91%"
    }
}
EOF
}


ES7_set_cluster_settings "$(curl_data_watermark)"
