#!/bin/bash
# AutoMQ Strimzi Cleanup Script
# Usage: ./cleanup.sh [--force]

set -e

NAMESPACE="${NAMESPACE:-automq}"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
print_info() { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
print_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }

FORCE=false
[[ "${1:-}" == "--force" || "${1:-}" == "-f" ]] && FORCE=true

echo ""
echo "=============================================="
echo " AutoMQ Strimzi Cleanup"
echo "=============================================="
echo ""

if [ "$FORCE" != true ]; then
    printf "This will remove AutoMQ and Strimzi from namespace '$NAMESPACE'. Continue? [y/N] "
    read -r REPLY
    [[ ! "$REPLY" =~ ^[Yy] ]] && { print_info "Cleanup cancelled."; exit 0; }
    echo ""
fi

print_info "Removing AutoMQ cluster..."
kubectl delete kafka my-cluster -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
kubectl delete kafkanodepool controller broker -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
print_info "✓ AutoMQ cluster removed"

print_info "Waiting for pods to terminate..."
kubectl wait --for=delete pods -l strimzi.io/cluster=my-cluster -n "$NAMESPACE" --timeout=120s 2>/dev/null || true

print_info "Removing PVCs..."
kubectl delete pvc -l strimzi.io/cluster=my-cluster -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
print_info "✓ PVCs removed"

print_info "Removing Strimzi Operator..."
helm uninstall automq-strimzi-operator --namespace "$NAMESPACE" 2>/dev/null || true
print_info "✓ Strimzi Operator removed"

print_info "Deleting namespace '$NAMESPACE'..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
print_info "✓ Namespace deleted"

echo ""
echo "=============================================="
echo " Cleanup Complete!"
echo "=============================================="
echo ""
print_info "Note: S3 buckets are not deleted. Remove them manually if needed:"
echo "  aws s3 rb s3://YOUR_DATA_BUCKET --force"
echo "  aws s3 rb s3://YOUR_OPS_BUCKET --force"
echo ""
