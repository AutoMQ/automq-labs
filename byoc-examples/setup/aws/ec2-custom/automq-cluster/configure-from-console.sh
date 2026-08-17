#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONSOLE_DIR="${1:-${SCRIPT_DIR}/../automq-console}"
readonly OUTPUT_FILE="${SCRIPT_DIR}/console.auto.tfvars.json"

for command_name in terraform jq; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Error: ${command_name} is required but was not found in PATH." >&2
    exit 1
  fi
done

if [[ ! -d "${CONSOLE_DIR}" ]]; then
  echo "Error: Console Terraform directory does not exist: ${CONSOLE_DIR}" >&2
  exit 1
fi

CONSOLE_DIR="$(cd "${CONSOLE_DIR}" && pwd)"
umask 077

console_outputs="$(mktemp "${TMPDIR:-/tmp}/automq-console-outputs.XXXXXX")"
rendered_tfvars="$(mktemp "${SCRIPT_DIR}/.console.auto.tfvars.json.XXXXXX")"
trap 'rm -f "${console_outputs}" "${rendered_tfvars}"' EXIT

if ! terraform -chdir="${CONSOLE_DIR}" output -json >"${console_outputs}"; then
  echo "Error: could not read Console outputs. Apply the automq-console root first." >&2
  exit 1
fi

if ! jq -e '
  . as $outputs |
  def required($name):
    $outputs[$name] as $output |
    if ($output | type) != "object" then
      error("Missing Terraform output: " + $name)
    elif ($output | has("value") | not) or $output.value == null then
      error("Terraform output has no value: " + $name)
    else
      $output.value
    end;
  {
    console_endpoint: required("console_endpoint"),
    console_access_key: required("console_initial_access_key"),
    console_secret_key: required("console_initial_secret_key"),
    environment_id: required("environment_id"),
    broker_networks: required("broker_networks"),
    data_bucket_name: required("data_bucket_name"),
    dns_zone_id: required("dns_zone_id"),
    instance_role_name: required("cluster_role_name")
  }
' "${console_outputs}" >"${rendered_tfvars}"; then
  echo "Error: Console state does not contain every output required by the Cluster root." >&2
  exit 1
fi

chmod 600 "${rendered_tfvars}"
mv -f "${rendered_tfvars}" "${OUTPUT_FILE}"

echo "Wrote ${OUTPUT_FILE} with permissions 0600."
