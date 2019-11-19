#!/usr/bin/env bash

source "${SCRIPT_DIR}"/../../lib/update-scripts-functions.sh
ES_URL=$ES_NONPROD_URL

upload_json
exec_jsonnet_and_upload
