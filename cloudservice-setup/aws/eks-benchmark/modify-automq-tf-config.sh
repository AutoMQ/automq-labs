#!/usr/bin/env bash

set -euo pipefail

# Paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
TFVARS_FILE="$SCRIPT_DIR/automq/terraform.tfvars"

# Checks
command -v terraform >/dev/null 2>&1 || { echo "[ERROR] terraform is not installed or not in PATH"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[ERROR] jq is required (brew install jq)"; exit 1; }

if [ ! -d "$TF_DIR" ]; then
  echo "[ERROR] Terraform directory not found: $TF_DIR"
  exit 1
fi

if [ ! -f "$TFVARS_FILE" ]; then
  echo "[WARN] tfvars file not found: $TFVARS_FILE"
  echo "[INFO] Creating from example if present..."
  if [ -f "$SCRIPT_DIR/automq/terraform.tfvars.example" ]; then
    cp "$SCRIPT_DIR/automq/terraform.tfvars.example" "$TFVARS_FILE"
    echo "[INFO] Created $TFVARS_FILE from example"
  else
    echo "[ERROR] Missing $TFVARS_FILE and no example found. Please create it."; exit 1
  fi
fi

echo "[INFO] Reading terraform outputs from: $TF_DIR"
OUT_JSON="$(terraform -chdir="$TF_DIR" output -json)"

get_output() {
  local key="$1"
  echo "$OUT_JSON" | jq -r ".[\"$key\"].value" 2>/dev/null || true
}

# Extract values from outputs
VPC_ID="$(get_output vpc_id)"
REGION="$(get_output region)"
AZ="$(get_output default_az)"
BYOC_ENDPOINT="$(get_output console_endpoint)"
AUTOMQ_ENV_ID="$(get_output automq_environment_id)"

# Basic validation
for kv in VPC_ID REGION AZ BYOC_ENDPOINT AUTOMQ_ENV_ID; do
  if [ -z "${!kv}" ] || [ "${!kv}" = "null" ]; then
    echo "[WARN] Output $kv is empty. Ensure you have applied Terraform in $TF_DIR and outputs are defined."
  fi
done

echo "[INFO] Please input AutoMQ BYOC credentials (from Console Service Account)"
read -r -p "automq_byoc_access_key_id: " BYOC_AKID
read -r -s -p "automq_byoc_secret_key (hidden): " BYOC_SK
echo

if [ -z "$BYOC_AKID" ] || [ -z "$BYOC_SK" ]; then
  echo "[ERROR] Both automq_byoc_access_key_id and automq_byoc_secret_key are required."
  exit 1
fi

# Helper: update or append key = "value"
update_tfvar() {
  local file="$1" key="$2" value="$3"
  local esc_val
  esc_val="$(printf '%s' "$value" | sed -e 's/[&|\\]/\\&/g')"
  if grep -E "^${key}[[:space:]]*=" "$file" >/dev/null 2>&1; then
    # macOS/BSD sed inline edit
    sed -i '' -E "s|^${key}[[:space:]]*=[[:space:]]*\"[^\"]*\"|${key} = \"${esc_val}\"|" "$file"
  else
    printf '%s\n' "${key} = \"${value}\"" >> "$file"
  fi
}

echo "[INFO] Updating $TFVARS_FILE"
update_tfvar "$TFVARS_FILE" vpc_id "$VPC_ID"
update_tfvar "$TFVARS_FILE" region "$REGION"
update_tfvar "$TFVARS_FILE" az "$AZ"
update_tfvar "$TFVARS_FILE" automq_byoc_endpoint "$BYOC_ENDPOINT"
update_tfvar "$TFVARS_FILE" automq_environment_id "$AUTOMQ_ENV_ID"
update_tfvar "$TFVARS_FILE" automq_byoc_access_key_id "$BYOC_AKID"
update_tfvar "$TFVARS_FILE" automq_byoc_secret_key "$BYOC_SK"

echo "[DONE] Updated $TFVARS_FILE with values from Terraform outputs and provided credentials."
echo "        - vpc_id=$VPC_ID"
echo "        - region=$REGION"
echo "        - az=$AZ"
echo "        - automq_byoc_endpoint=$BYOC_ENDPOINT"
echo "        - automq_environment_id=$AUTOMQ_ENV_ID"