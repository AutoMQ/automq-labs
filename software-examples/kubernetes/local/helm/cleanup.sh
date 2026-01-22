#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

print_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

print_header() {
    echo ""
    echo "=============================================="
    echo " AutoMQ Cleanup"
    echo "=============================================="
    echo ""
}

# Cleanup AutoMQ
cleanup_automq() {
    print_info "Removing AutoMQ..."
    
    if helm status automq &> /dev/null; then
        helm uninstall automq
        print_info "✓ AutoMQ helm release removed"
    else
        print_warn "AutoMQ helm release not found, skipping..."
    fi
    
    # Clean up PVCs
    local pvc_count
    pvc_count=$(kubectl get pvc -l app.kubernetes.io/name=automq-enterprise --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$pvc_count" -gt 0 ]; then
        kubectl delete pvc -l app.kubernetes.io/name=automq-enterprise
        print_info "✓ AutoMQ PVCs removed"
    fi
}

# Cleanup MinIO
cleanup_minio() {
    print_info "Removing MinIO..."
    
    if helm status minio &> /dev/null; then
        helm uninstall minio
        print_info "✓ MinIO helm release removed"
    else
        print_warn "MinIO helm release not found, skipping..."
    fi
    
    # Clean up PVCs
    local pvc_count
    pvc_count=$(kubectl get pvc -l app=minio --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$pvc_count" -gt 0 ]; then
        kubectl delete pvc -l app=minio
        print_info "✓ MinIO PVCs removed"
    fi
}

# Cleanup generated files
cleanup_files() {
    print_info "Removing generated files..."
    
    if [ -f "automq-values.yaml" ]; then
        rm -f automq-values.yaml
        print_info "✓ automq-values.yaml removed"
    fi
}

# Print completion message
print_complete() {
    echo ""
    echo "=============================================="
    echo " Cleanup Complete!"
    echo "=============================================="
    echo ""
    print_info "All AutoMQ and MinIO resources have been removed."
    echo ""
}

# Main
main() {
    print_header
    
    # Confirm cleanup
    printf "This will remove AutoMQ and MinIO from your cluster. Continue? [y/N] "
    read -r REPLY
    
    case "$REPLY" in
        [Yy]|[Yy][Ee][Ss])
            ;;
        *)
            print_info "Cleanup cancelled."
            exit 0
            ;;
    esac
    
    echo ""
    cleanup_automq
    cleanup_minio
    cleanup_files
    print_complete
}

main "$@"
