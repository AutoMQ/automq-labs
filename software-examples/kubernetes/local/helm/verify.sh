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

print_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

print_header() {
    echo ""
    echo "=============================================="
    echo " AutoMQ Installation Verification"
    echo "=============================================="
    echo ""
}

# Check pod status
check_pods() {
    print_info "Checking AutoMQ pods status..."
    
    local ready_pods
    local total_pods
    ready_pods=$(kubectl get pods -l app.kubernetes.io/name=automq-enterprise --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    total_pods=$(kubectl get pods -l app.kubernetes.io/name=automq-enterprise --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$total_pods" -eq 0 ]; then
        print_error "No AutoMQ pods found. Please ensure AutoMQ is installed."
        exit 1
    fi
    
    echo ""
    kubectl get pods -l app.kubernetes.io/name=automq-enterprise
    echo ""
    
    if [ "$ready_pods" -ne "$total_pods" ]; then
        print_error "Not all pods are running ($ready_pods/$total_pods ready)"
        print_info "Waiting for pods to be ready..."
        kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=automq-enterprise --timeout=300s
    fi
    
    print_info "✓ All AutoMQ pods are running"
}

# Create test topic
create_test_topic() {
    print_info "Creating test topic..."
    
    kubectl run kafka-client-test --rm -it --restart=Never \
        --image=confluentinc/cp-kafka:latest \
        --command -- \
        kafka-topics --bootstrap-server automq-automq-enterprise-controller-headless:9092 \
        --create --topic test-topic --partitions 3 --replication-factor 1 \
        --if-not-exists
    
    print_info "✓ Test topic created successfully"
}

# List topics
list_topics() {
    print_info "Listing topics..."
    echo ""
    
    kubectl run kafka-client-list --rm -it --restart=Never \
        --image=confluentinc/cp-kafka:latest \
        --command -- \
        kafka-topics --bootstrap-server automq-automq-enterprise-controller-headless:9092 \
        --list
}

# Print success message
print_success() {
    echo ""
    echo "=============================================="
    echo " Verification Complete!"
    echo "=============================================="
    echo ""
    print_info "AutoMQ is running and accessible."
    echo ""
    echo "Bootstrap server (internal): automq-automq-enterprise-controller-headless:9092"
    echo ""
    echo "To produce messages:"
    echo "  kubectl run kafka-producer --rm -it --restart=Never --image=confluentinc/cp-kafka:latest -- \\"
    echo "    kafka-console-producer --bootstrap-server automq-automq-enterprise-controller-headless:9092 --topic test-topic"
    echo ""
    echo "To consume messages:"
    echo "  kubectl run kafka-consumer --rm -it --restart=Never --image=confluentinc/cp-kafka:latest -- \\"
    echo "    kafka-console-consumer --bootstrap-server automq-automq-enterprise-controller-headless:9092 --topic test-topic --from-beginning"
    echo ""
}

# Main
main() {
    print_header
    check_pods
    create_test_topic
    list_topics
    print_success
}

main "$@"
