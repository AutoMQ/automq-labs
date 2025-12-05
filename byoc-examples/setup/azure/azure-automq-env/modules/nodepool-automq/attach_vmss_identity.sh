#!/usr/bin/env bash
set -euo pipefail

# Usage: attach_vmss_identity.sh <CLUSTER_ID> <NODEPOOL_NAME> <IDENTITY_ID>
CLUSTER_ID=${1:-}
NODEPOOL_NAME=${2:-}
IDENTITY_ID=${3:-}

if [[ -z "$CLUSTER_ID" || -z "$NODEPOOL_NAME" || -z "$IDENTITY_ID" ]]; then
  echo "Usage: $0 <CLUSTER_ID> <NODEPOOL_NAME> <IDENTITY_ID>" >&2
  exit 1
fi

# Extract RG and cluster name from resource ID
CLUSTER_RG=$(echo "$CLUSTER_ID" | awk -F'/' '{print $5}')
CLUSTER_NAME=$(echo "$CLUSTER_ID" | awk -F'/' '{print $9}')

NODE_RG=$(az aks show --resource-group "$CLUSTER_RG" --name "$CLUSTER_NAME" --query nodeResourceGroup -o tsv)

VMSS_NAME=$(az vmss list -g "$NODE_RG" -o json | jq -r --arg pool "$NODEPOOL_NAME" '.[] | select(.tags["aks-managed-poolName"]==$pool) | .name')

if [[ -z "$VMSS_NAME" || "$VMSS_NAME" == "null" ]]; then
  echo "Failed to locate VMSS for pool $NODEPOOL_NAME in $NODE_RG" >&2
  exit 2
fi

echo "Assigning identity $IDENTITY_ID to VMSS $VMSS_NAME in $NODE_RG"
az vmss identity assign -g "$NODE_RG" -n "$VMSS_NAME" --identities "$IDENTITY_ID" 1>/dev/null

echo "Done"
