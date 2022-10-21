#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "${SCRIPT_DIR}" || exit

source "grafana-tools.lib.sh"

if [[ -e .env.sh ]]; then
  source ".env.sh"
fi

if ! [ -d generated ]; then
  echo "No dashboards, generating..."
  # we dont source the file as it would mess up `dry_run` flag
  bash generate-dashboards.sh
fi

IFS=$'\n\t'
TEMPFILE="tempfile"

FILE="${SCRIPT_DIR}/autogenerated-service-health-dashboards.json"

usage() {
  cat <<-EOF
  Usage [Dh]

  DESCRIPTION
    This script checks the existence of any dashboards defined in
    "dashboards/**/*.dashboard.jsonnet" files and collates the result
    in a JSON file

    GRAFANA_API_TOKEN must be set in the environment

    Useful for testing.

  FLAGS
    -D  run in Dry-run
    -h  help

EOF
}

while getopts ":Dh" o; do
  case "${o}" in
    D)
      dry_run="true"
      ;;
    h)
      usage
      exit 0
      ;;
    *) ;;

  esac
done

shift $((OPTIND - 1))

dry_run=${dry_run:-}

if [[ -z $dry_run && -z ${GRAFANA_API_TOKEN:-} ]]; then
  echo "You must set GRAFANA_API_TOKEN to use this script, or run in dry run mode"
  usage
  exit 1
fi

prepare

trap 'rm -rf "${TEMPFILE}"' EXIT

# some $FILE needs to exist to avoid jsonnet error in libsonnet/service-maturity/levels.libsonnet
if [ ! -f "$FILE" ]; then
  echo "{}" >"$FILE"
fi

find -P generated -name '*.json' | sed 's/generated\///' | while read -r line; do
  relative=${line#"./"}
  folder=${GRAFANA_FOLDER:-$(dirname "$relative")}

  cat generated/$line | jq -c | while IFS= read -r dashboard; do
    # Use http1.1 and gzip compression to workaround unexplainable random errors that
    # occur when uploading some dashboards
    uid=$(echo "${dashboard}" | jq -r '.uid')
    if response=$(call_grafana_api "https://dashboards.gitlab.net/api/dashboards/uid/$uid"); then
      url=$(echo "${response}" | jq '.meta.url' | tr -d '"')
      fullurl="https://dashboards.gitlab.net$url"
      echo "${folder},${fullurl}" >>$TEMPFILE
    fi
    echo "Processed dashboards for $uid"
  done
done

if [[ -n $dry_run ]]; then
  jq -R -n '[inputs|split(",")]| group_by(.[0]) | map({(.[0][0]): [.[][1]]}) | add | .[]|=sort' $TEMPFILE
else
  jq -R -n '[inputs|split(",")]| group_by(.[0]) | map({(.[0][0]): [.[][1]]}) | add | .[]|=sort' $TEMPFILE >"$FILE"
fi
