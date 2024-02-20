#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

REPO_DIR=$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.."
  pwd
)

cd "${REPO_DIR}"

# Check that jsonnet-tool is installed
"${REPO_DIR}/scripts/ensure-jsonnet-tool.sh"

export GL_GENERATE_CONFIG_HEADER="# WARNING. DO NOT EDIT THIS FILE BY HAND. RUN ./scripts/generate-all-reference-architecture-configs.sh TO GENERATE IT. YOUR CHANGES WILL BE OVERRIDDEN"

# Generate all the reference architectures, without overrides
for parent_dir in reference-architectures/*; do
  if [[ ! -f "${parent_dir}/src/generate.jsonnet" ]]; then
    continue
  fi

  source_dir="${parent_dir}/src"
  output_dir="${parent_dir}/config"

  rm -rf "${output_dir}"

  "${REPO_DIR}"/scripts/generate-reference-architecture-config.sh "${source_dir}" "${output_dir}"
done

# Generate the documentation
"${REPO_DIR}"/scripts/generate-reference-architecture-docs.sh
