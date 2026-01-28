#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

AUTOMQ_DIR="automq-kafka-enterprise_5.3.4"

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

stop_automq() {
    print_info "Stopping AutoMQ nodes..."
    
    if [ -d "$AUTOMQ_DIR" ]; then
        "$AUTOMQ_DIR/bin/kafka-server-stop.sh" 2>/dev/null || true
        sleep 2
        print_info "✓ AutoMQ nodes stopped"
    else
        print_warn "AutoMQ directory not found, skipping..."
    fi
}

stop_minio() {
    print_info "Stopping MinIO..."
    
    if [ -f "minio/docker-compose.yml" ]; then
        docker compose -f minio/docker-compose.yml down -v 2>/dev/null || true
        print_info "✓ MinIO stopped and volumes removed"
    else
        print_warn "MinIO docker-compose.yml not found, skipping..."
    fi
}

remove_data() {
    print_info "Removing data directories..."
    
    rm -rf /tmp/automq-data-* 2>/dev/null || true
    print_info "✓ Data directories removed"
}

remove_generated_files() {
    if [ "$1" = "--all" ]; then
        print_info "Removing generated files..."
        
        rm -rf "$AUTOMQ_DIR" 2>/dev/null || true
        rm -rf minio 2>/dev/null || true
        rm -f automq-enterprise-*.tgz 2>/dev/null || true
        
        print_info "✓ Generated files removed"
    fi
}

print_complete() {
    echo ""
    echo "=============================================="
    echo " Cleanup Complete!"
    echo "=============================================="
    echo ""
    print_info "All AutoMQ and MinIO resources have been removed."
    echo ""
}

main() {
    print_header
    
    if [ "$1" != "-y" ] && [ "$1" != "--yes" ] && [ "$1" != "--all" ]; then
        printf "This will stop AutoMQ and MinIO, and remove data. Continue? [y/N] "
        read -r REPLY
        
        case "$REPLY" in
            [Yy]|[Yy][Ee][Ss])
                ;;
            *)
                print_info "Cleanup cancelled."
                exit 0
                ;;
        esac
    fi
    
    echo ""
    stop_automq
    stop_minio
    remove_data
    remove_generated_files "$1"
    print_complete
}

main "$@"
