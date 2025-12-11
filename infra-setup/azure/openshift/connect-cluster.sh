#!/bin/bash
# Script to connect to Azure Red Hat OpenShift cluster

set -e

# Get cluster information from terraform.tfvars or use defaults
CLUSTER_NAME="${CLUSTER_NAME:-demobeihai}"
RESOURCE_GROUP="${RESOURCE_GROUP:-AutoMQ-lab-openshift}"

echo "=========================================="
echo "Connecting to Azure OpenShift Cluster"
echo "=========================================="
echo "Cluster Name: $CLUSTER_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo ""

# Check if Azure CLI is installed and logged in
if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI (az) is not installed."
    echo "Please install it from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    echo "Error: Not logged in to Azure CLI."
    echo "Please run: az login"
    exit 1
fi

# Get API server URL
echo "Getting API server URL..."
API_URL=$(az aro show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --query "apiserverProfile.url" \
    --output tsv 2>/dev/null)

if [ -z "$API_URL" ]; then
    echo "Error: Could not get API server URL."
    echo "Please verify that the cluster exists and you have access to it."
    exit 1
fi

echo "API Server URL: $API_URL"
echo ""

# Get console URL
CONSOLE_URL=$(az aro show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --query "consoleProfile.url" \
    --output tsv 2>/dev/null)

if [ -n "$CONSOLE_URL" ]; then
    echo "Console URL: $CONSOLE_URL"
    echo ""
fi

# Get kubeadmin credentials
echo "Getting kubeadmin credentials..."
CREDS_JSON=$(az aro list-credentials \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --output json 2>/dev/null)

if [ -z "$CREDS_JSON" ]; then
    echo "Error: Could not get cluster credentials."
    exit 1
fi

# Extract username and password
if command -v jq &> /dev/null; then
    KUBEADMIN_USERNAME=$(echo "$CREDS_JSON" | jq -r ".kubeadminUsername")
    KUBEADMIN_PASSWORD=$(echo "$CREDS_JSON" | jq -r ".kubeadminPassword")
else
    KUBEADMIN_USERNAME=$(echo "$CREDS_JSON" | grep -o '"kubeadminUsername": "[^"]*"' | cut -d'"' -f4)
    KUBEADMIN_PASSWORD=$(echo "$CREDS_JSON" | grep -o '"kubeadminPassword": "[^"]*"' | cut -d'"' -f4)
fi

if [ -z "$KUBEADMIN_USERNAME" ] || [ -z "$KUBEADMIN_PASSWORD" ]; then
    echo "Error: Could not extract credentials."
    exit 1
fi

echo "Username: $KUBEADMIN_USERNAME"
echo ""

# Check if oc CLI is installed
if ! command -v oc &> /dev/null; then
    echo "Warning: OpenShift CLI (oc) is not installed."
    echo "Please install it from: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/"
    echo ""
    echo "You can also use kubectl with the following kubeconfig:"
    echo ""
    echo "To get kubeconfig, run:"
    echo "  az aro get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME"
    echo ""
    echo "Or manually configure kubectl:"
    echo "  kubectl config set-cluster $CLUSTER_NAME --server=$API_URL --insecure-skip-tls-verify=true"
    echo "  kubectl config set-credentials kubeadmin --username=$KUBEADMIN_USERNAME --password=$KUBEADMIN_PASSWORD"
    echo "  kubectl config set-context $CLUSTER_NAME --cluster=$CLUSTER_NAME --user=kubeadmin"
    echo "  kubectl config use-context $CLUSTER_NAME"
    exit 0
fi

# Login using oc
echo "Logging in to OpenShift cluster..."
oc login "$API_URL" \
    --username="$KUBEADMIN_USERNAME" \
    --password="$KUBEADMIN_PASSWORD" \
    --insecure-skip-tls-verify=true

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "Successfully logged in!"
    echo "=========================================="
    echo ""
    echo "You can now use 'oc' or 'kubectl' commands."
    echo ""
    echo "Try these commands:"
    echo "  oc get nodes"
    echo "  oc get projects"
    echo "  kubectl get namespaces"
    echo ""
    if [ -n "$CONSOLE_URL" ]; then
        echo "Access the web console at: $CONSOLE_URL"
    fi
else
    echo "Error: Failed to log in to the cluster."
    exit 1
fi

