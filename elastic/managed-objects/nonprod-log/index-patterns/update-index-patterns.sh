#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
export ES_URL=$ES_NONPROD_URL
source "${SCRIPT_DIR}"/../../lib/update-scripts-functions.sh

kibana_upload_json "api/saved_objects/index-pattern/"
