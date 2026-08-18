#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
CONSOLE_DIR="${1:-${SCRIPT_DIR}/../automq-console}"
OUTPUT_FILE="${SCRIPT_DIR}/console.auto.tfvars.json"
readonly OUTPUT_FILE

console_outputs=""
rendered_tfvars=""

cleanup() {
  if [[ -n "${console_outputs}" ]]; then
    rm -f -- "${console_outputs}"
  fi
  if [[ -n "${rendered_tfvars}" ]]; then
    rm -f -- "${rendered_tfvars}"
  fi
}

trap cleanup EXIT

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
  def required_string($name):
    required($name) as $value |
    if ($value | type) != "string" or ($value | test("\\S") | not) then
      error("Terraform output must be a non-empty string: " + $name)
    else
      $value
    end;
  def required_array($name):
    required($name) as $value |
    if ($value | type) != "array" or ($value | length) == 0 then
      error("Terraform output must be a non-empty array: " + $name)
    else
      $value
    end;
  {
    console_endpoint: required_string("console_endpoint"),
    console_access_key: required_string("console_initial_access_key"),
    console_secret_key: required_string("console_initial_secret_key"),
    environment_id: required_string("environment_id"),
    broker_networks: required_array("broker_networks"),
    data_bucket_name: required_string("data_bucket_name"),
    dns_zone_id: required_string("dns_zone_id"),
    instance_role_name: required_string("cluster_role_name")
  }
' "${console_outputs}" >"${rendered_tfvars}"; then
  echo "Error: Console state does not contain every output required by the Cluster root." >&2
  exit 1
fi

chmod 600 "${rendered_tfvars}"
mv -f "${rendered_tfvars}" "${OUTPUT_FILE}"
rendered_tfvars=""

echo "Wrote ${OUTPUT_FILE} with permissions 0600."
