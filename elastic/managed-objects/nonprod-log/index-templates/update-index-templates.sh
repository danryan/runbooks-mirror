#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
export ES_URL=$ES_NONPROD_URL
source "${SCRIPT_DIR}"/../../lib/update-scripts-functions.sh
source "${SCRIPT_DIR}"/../../indices/indices-array.sh
template_name='nonprod-log_index_template.libsonnet'

envs=(gstg ops pre db-benchmarking)
for env in "${envs[@]}"; do
  # shellcheck disable=SC2154
  for index in "${indices[@]}"; do
    ES7_index-template_exec_jsonnet_and_upload_json "$template_name" "$index" "$env"
  done
done

ES7_put_json "_template/"
