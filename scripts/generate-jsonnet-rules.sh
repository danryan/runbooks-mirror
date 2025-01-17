#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

REPO_DIR=$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.."
  pwd
)

if [[ "$(uname)" == "Darwin" ]]; then
  if ! hash grealpath; then
    echo >&2 "grealpath not found, please install it via: brew install coreutils"
    exit 1
  fi
  REALPATH=grealpath
else
  REALPATH=realpath
fi

# Check that jsonnet-tool is installed
"${REPO_DIR}/scripts/ensure-jsonnet-tool.sh"

function render_multi_jsonnet() {
  local dest_dir
  local filename
  local warning
  dest_dir="$1"
  # Expand and normalize how we present paths, so we can use whatever form we like as input:
  # ./generate-jsonnet-rules.sh ./path/to/some.jsonnet
  # Will result in the same $filename and content in $warning as:
  # ./generate-jsonnet-rules.sh path/to/some.jsonnet
  filename="./$($REALPATH --relative-to="$REPO_DIR" "$2")"
  warning="# WARNING. DO NOT EDIT THIS FILE BY HAND. USE ${filename} TO GENERATE IT
# YOUR CHANGES WILL BE OVERRIDDEN"

  local source_file
  local sha256sum_file
  local cache_out_file
  source_file="$filename"
  sha256sum_file="${REPO_DIR}/.cache/$source_file.sha256sum"
  cache_out_file="${REPO_DIR}/.cache/$source_file.out"

  if [[ ${GL_JSONNET_CACHE_SKIP:-} != 'true' ]]; then
    mkdir -p "$(dirname "$sha256sum_file")" "$(dirname "$cache_out_file")"

    if [[ -f $cache_out_file ]] && [[ -f $sha256sum_file ]] && sha256sum --check --status <"$sha256sum_file"; then
      while read -r file; do
        mkdir -p "$(dirname "$file")"
        cp "${REPO_DIR}/.cache/$file" "$file"
      done <"$cache_out_file"
      cat "$cache_out_file"
      return 0
    fi

    if [[ ${GL_JSONNET_CACHE_DEBUG:-} == 'true' ]]; then
      echo >&2 "jsonnet_cache: miss: $source_file"
    fi
  fi

  out="$(
    jsonnet-tool yaml \
      --multi "$dest_dir" \
      --header "${warning}" \
      -J "${REPO_DIR}/libsonnet/" \
      -J "${REPO_DIR}/metrics-catalog/" \
      -J "${REPO_DIR}/services/" \
      -J "${REPO_DIR}/vendor/" \
      -P name -P interval -P partial_response_strategy \
      -P alert -P for -P annotations -P record -P labels -P expr \
      -P title -P description \
      --prefix "autogenerated-" \
      "${source_file}"
  )"
  echo "$out"

  if [[ ${GL_JSONNET_CACHE_SKIP:-} != 'true' ]]; then
    echo "$out" >"$cache_out_file"
    for file in $out; do
      mkdir -p "$(dirname "${REPO_DIR}/.cache/$file")"
      cp "$file" "${REPO_DIR}/.cache/$file"
    done
    jsonnet-deps \
      -J "${REPO_DIR}/dashboards/" \
      -J "${REPO_DIR}/libsonnet/" \
      -J "${REPO_DIR}/metrics-catalog/" \
      -J "${REPO_DIR}/services/" \
      -J "${REPO_DIR}/vendor/" \
      "$source_file" | xargs sha256sum >"$sha256sum_file"
    echo "$source_file" "${REPO_DIR}/.tool-versions" | xargs realpath | xargs sha256sum >>"$sha256sum_file"
  fi
}

if [[ $# == 0 ]]; then
  cd "${REPO_DIR}"

  find ./mimir-rules-jsonnet -name '*.jsonnet' -print0 | xargs -0 -P "$(nproc)" -n 1 ./scripts/generate-jsonnet-rules.sh
else
  for file in "$@"; do
    source_dir=$(dirname "${file}")
    render_multi_jsonnet "${source_dir%-jsonnet}" "${file}"
  done
fi
