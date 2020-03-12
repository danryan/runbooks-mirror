#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

REPO_DIR=$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.."
  pwd
)

# Convert the service catalog yaml into a JSON file in a format thats consumable by jsonnet
ruby -rjson -ryaml -e "puts YAML.load(ARGF.read).to_json" "${REPO_DIR}/services/service-catalog.yml" >"${REPO_DIR}/services/service_catalog.json"

tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'generate-jsonnet-rules')
trap 'rm -rf "${tmpdir}"' EXIT

function render_multi_jsonnet() {
  local filename="$1"

  output_files="$(jsonnet -J "${REPO_DIR}/rules-jsonnet" -J "${REPO_DIR}/metrics-catalog" -J "${REPO_DIR}/services" --string --multi "${tmpdir}" "${filename}")"

  warning="# WARNING. DO NOT EDIT THIS FILE BY HAND. USE ${filename} TO GENERATE IT
# YOUR CHANGES WILL BE OVERRIDDEN"

  for i in ${output_files}; do
    local b
    b=$(basename "${i}")

    (
      echo "$warning"
      "${REPO_DIR}/scripts/fix-prom-rules.rb" "${i}"
    ) >"${REPO_DIR}/rules/autogenerated-${b}"

    rm -f "${i}"
    echo "${REPO_DIR}/rules/autogenerated-${b}"
  done
}

if [[ $# == 0 ]]; then
  cd "${REPO_DIR}"
  for file in ./rules-jsonnet/*; do
    render_multi_jsonnet "${file}"
  done
else
  for file in "$@"; do
    render_multi_jsonnet "${file}"
  done
fi
