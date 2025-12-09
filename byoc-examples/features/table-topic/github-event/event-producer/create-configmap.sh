#!/bin/bash
# Script to create ConfigMap from source files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRODUCER_DIR="$(cd "${SCRIPT_DIR}" && pwd)"
CONFIGMAP_NAME="github-event-producer-code"
NAMESPACE="default"

echo "Creating ConfigMap ${CONFIGMAP_NAME} from source files..."
echo "Source directory: ${PRODUCER_DIR}"
echo ""

# Create ConfigMap from source files
kubectl create configmap ${CONFIGMAP_NAME} \
  --from-file="${PRODUCER_DIR}/event_producer.py" \
  --from-file="${PRODUCER_DIR}/requirements.txt" \
  --from-file="${PRODUCER_DIR}/github_event.avsc" \
  --namespace=${NAMESPACE} \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ ConfigMap ${CONFIGMAP_NAME} created/updated successfully!"
echo ""
echo "To view the ConfigMap:"
echo "  kubectl get configmap ${CONFIGMAP_NAME} -n ${NAMESPACE}"
echo ""
echo "To delete the ConfigMap:"
echo "  kubectl delete configmap ${CONFIGMAP_NAME} -n ${NAMESPACE}"

