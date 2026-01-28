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

print_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

print_header() {
    echo ""
    echo "=============================================="
    echo " AutoMQ Storage Format"
    echo "=============================================="
    echo ""
}

check_automq_dir() {
    if [ ! -d "$AUTOMQ_DIR" ]; then
        print_error "AutoMQ directory not found. Please run setup.sh first."
        exit 1
    fi
}

format_storage() {
    print_info "Generating cluster ID..."
    
    local cluster_id
    cluster_id=$("$AUTOMQ_DIR/bin/kafka-storage.sh" random-uuid)
    
    print_info "Cluster ID: $cluster_id"
    echo ""
    
    print_info "Formatting Node 0..."
    "$AUTOMQ_DIR/bin/kafka-storage.sh" format -t "$cluster_id" -c "$AUTOMQ_DIR/config/kraft/node0.properties"
    
    print_info "Formatting Node 1..."
    "$AUTOMQ_DIR/bin/kafka-storage.sh" format -t "$cluster_id" -c "$AUTOMQ_DIR/config/kraft/node1.properties"
    
    print_info "Formatting Node 2..."
    "$AUTOMQ_DIR/bin/kafka-storage.sh" format -t "$cluster_id" -c "$AUTOMQ_DIR/config/kraft/node2.properties"
    
    echo ""
    print_info "All nodes formatted successfully!"
}

print_next_steps() {
    echo ""
    echo "=============================================="
    echo " Format Complete!"
    echo "=============================================="
    echo ""
    echo "Now you can start the cluster. Run these commands in 3 separate terminals:"
    echo ""
    echo "# Terminal 1 - Node 0"
    echo "cd ${AUTOMQ_DIR}"
    echo "export KAFKA_S3_ACCESS_KEY=admin"
    echo "export KAFKA_S3_SECRET_KEY=automq_demo_secret"
    echo "export KAFKA_HEAP_OPTS=\"-Xmx2g -Xms2g\""
    echo "bin/kafka-server-start.sh config/kraft/node0.properties"
    echo ""
    echo "# Terminal 2 - Node 1"
    echo "cd ${AUTOMQ_DIR}"
    echo "export KAFKA_S3_ACCESS_KEY=admin"
    echo "export KAFKA_S3_SECRET_KEY=automq_demo_secret"
    echo "export KAFKA_HEAP_OPTS=\"-Xmx2g -Xms2g\""
    echo "bin/kafka-server-start.sh config/kraft/node1.properties"
    echo ""
    echo "# Terminal 3 - Node 2"
    echo "cd ${AUTOMQ_DIR}"
    echo "export KAFKA_S3_ACCESS_KEY=admin"
    echo "export KAFKA_S3_SECRET_KEY=automq_demo_secret"
    echo "export KAFKA_HEAP_OPTS=\"-Xmx2g -Xms2g\""
    echo "bin/kafka-server-start.sh config/kraft/node2.properties"
    echo ""
}

main() {
    print_header
    check_automq_dir
    format_storage
    print_next_steps
}

main "$@"
