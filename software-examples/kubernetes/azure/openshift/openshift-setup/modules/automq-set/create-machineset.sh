#!/usr/bin/env bash
set -euo pipefail

# Script to create OpenShift Machine Set for AutoMQ nodes
# This script should be run after the cluster is created and you're logged in with oc

CLUSTER_NAME="${1:-}"
RESOURCE_GROUP="${2:-}"
SUBNET_ID="${3:-}"
VNET_NAME="${4:-}"
SUBNET_NAME="${5:-}"
NETWORK_RG="${6:-}"
VM_SIZE="${7:-Standard_D4s_v3}"
NODE_COUNT="${8:-3}"
DISK_SIZE_GB="${9:-128}"
LOCATION="${10:-}"

if [[ -z "$CLUSTER_NAME" || -z "$RESOURCE_GROUP" || -z "$SUBNET_ID" || -z "$VNET_NAME" || -z "$SUBNET_NAME" || -z "$NETWORK_RG" ]]; then
  echo "Usage: $0 <cluster-name> <resource-group> <subnet-id> <vnet-name> <subnet-name> <network-resource-group> [vm-size] [node-count] [disk-size-gb] [location]"
  exit 1
fi

# Get cluster information
CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}' 2>/dev/null || echo "")
if [[ -z "$CLUSTER_ID" ]]; then
  echo "Error: Could not get cluster ID. Make sure you're logged into the OpenShift cluster."
  exit 1
fi

# Get image configuration from existing worker machine (to match cluster's OpenShift version)
# Find any existing worker machine to get the image config
WORKER_MACHINE=$(oc get machines -n openshift-machine-api -o name | grep worker | head -1 | cut -d/ -f2)
if [[ -n "$WORKER_MACHINE" ]]; then
  IMAGE_OFFER=$(oc get machine "$WORKER_MACHINE" -n openshift-machine-api -o jsonpath='{.spec.providerSpec.value.image.offer}' 2>/dev/null || echo "aro4")
  IMAGE_PUBLISHER=$(oc get machine "$WORKER_MACHINE" -n openshift-machine-api -o jsonpath='{.spec.providerSpec.value.image.publisher}' 2>/dev/null || echo "azureopenshift")
  IMAGE_SKU=$(oc get machine "$WORKER_MACHINE" -n openshift-machine-api -o jsonpath='{.spec.providerSpec.value.image.sku}' 2>/dev/null || echo "aro_418")
  IMAGE_VERSION=$(oc get machine "$WORKER_MACHINE" -n openshift-machine-api -o jsonpath='{.spec.providerSpec.value.image.version}' 2>/dev/null || echo "")
  IMAGE_TYPE=$(oc get machine "$WORKER_MACHINE" -n openshift-machine-api -o jsonpath='{.spec.providerSpec.value.image.type}' 2>/dev/null || echo "MarketplaceNoPlan")
else
  # Fallback to default values if no worker machine found
  echo "Warning: No existing worker machine found, using default image configuration"
  IMAGE_OFFER="aro4"
  IMAGE_PUBLISHER="azureopenshift"
  IMAGE_SKU="aro_418"
  IMAGE_VERSION=""
  IMAGE_TYPE="MarketplaceNoPlan"
fi

# Get location if not provided
if [[ -z "$LOCATION" ]]; then
  LOCATION=$(az aro show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --query "location" -o tsv 2>/dev/null || echo "eastus")
fi

echo "Creating Machine Sets for AutoMQ nodes..."
echo "Cluster ID: $CLUSTER_ID"
echo "Subnet ID: $SUBNET_ID"
echo "Subnet Name: $SUBNET_NAME"
echo "VNet Name: $VNET_NAME"
echo "Network Resource Group: $NETWORK_RG"
echo "VM Size: $VM_SIZE"
echo "Node Count: $NODE_COUNT per zone"

# Create Machine Set for each availability zone (1, 2, 3)
for ZONE in 1 2 3; do
  REPLICAS=$((NODE_COUNT / 3))
  if [[ $ZONE -le $((NODE_COUNT % 3)) ]]; then
    REPLICAS=$((REPLICAS + 1))
  fi

  MACHINESET_NAME="${CLUSTER_ID}-automq-${LOCATION}${ZONE}"

  cat <<EOF | oc apply -f -
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
  name: ${MACHINESET_NAME}
  namespace: openshift-machine-api
spec:
  replicas: ${REPLICAS}
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
      machine.openshift.io/cluster-api-machineset: ${MACHINESET_NAME}
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
        machine.openshift.io/cluster-api-machine: ${MACHINESET_NAME}
        machine.openshift.io/cluster-api-machineset: ${MACHINESET_NAME}
        node-role.kubernetes.io/worker: ""
        node-role.kubernetes.io/automq: ""
    spec:
      metadata:
        labels:
          node-role.kubernetes.io/worker: ""
          node-role.kubernetes.io/automq: ""
          dedicated: "automq"
      taints:
        - effect: NoSchedule
          key: dedicated
          value: automq
      providerSpec:
        value:
          apiVersion: azureproviderconfig.openshift.io/v1beta1
          credentialsSecret:
            name: azure-cloud-credentials
            namespace: openshift-machine-api
          kind: AzureMachineProviderSpec
          location: ${LOCATION}
          metadata:
            creationTimestamp: null
          networkResourceGroup: ${NETWORK_RG}
          publicIP: false
          resourceGroup: ${NETWORK_RG}
          subnet: ${SUBNET_NAME}
          userDataSecret:
            name: worker-user-data
            namespace: openshift-machine-api
          vmSize: ${VM_SIZE}
          vnet: ${VNET_NAME}
          zone: "${ZONE}"
          image:
            offer: ${IMAGE_OFFER}
            publisher: ${IMAGE_PUBLISHER}
            resourceID: ""
            sku: ${IMAGE_SKU}
            type: ${IMAGE_TYPE}
            version: ${IMAGE_VERSION}
          osDisk:
            diskSizeGB: ${DISK_SIZE_GB}
            managedDisk:
              storageAccountType: Premium_LRS
            osType: Linux
EOF

  echo "Created Machine Set: $MACHINESET_NAME with $REPLICAS replicas"
done

echo ""
echo "Machine Sets created successfully!"
echo "Wait a few minutes for nodes to be provisioned, then check with:"
echo "  oc get machinesets -n openshift-machine-api"
echo "  oc get nodes -l node-role.kubernetes.io/automq"

