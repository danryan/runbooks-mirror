#!/bin/bash

find ./mimir-rules -type f -path '*autogenerated*yml' -delete
find ./mimir-rules -type d -empty -delete
arr=(
  "./scripts/generate-jsonnet-rules.sh"
  "./scripts/generate-docs"
  "./scripts/generate-all-reference-architecture-configs.sh"
  "./scripts/generate-service-dashboards"
)
commands=$(printf "%s\n" "${arr[@]}")
echo "$commands" | xargs -I {} -P "$(nproc)" bash -c '{}'
