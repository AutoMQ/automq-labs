#!/bin/bash
# Script to create ConfigMap from source files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTEBOOK_DIR="$(cd "${SCRIPT_DIR}" && pwd)"
CONFIGMAP_NAME="github-event-notebook-code"
NAMESPACE="default"

echo "Creating ConfigMap ${CONFIGMAP_NAME} from source files..."
echo "Source directory: ${NOTEBOOK_DIR}"
echo ""

# Create ConfigMap from source files
kubectl create configmap ${CONFIGMAP_NAME} \
  --from-file="${NOTEBOOK_DIR}/analysis.py" \
  --from-file="${NOTEBOOK_DIR}/requirements.txt" \
  --namespace=${NAMESPACE} \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ ConfigMap ${CONFIGMAP_NAME} created/updated successfully!"
echo ""
echo "To view the ConfigMap:"
echo "  kubectl get configmap ${CONFIGMAP_NAME} -n ${NAMESPACE}"
echo ""
echo "To delete the ConfigMap:"
echo "  kubectl delete configmap ${CONFIGMAP_NAME} -n ${NAMESPACE}"

