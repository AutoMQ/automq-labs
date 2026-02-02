#!/bin/bash
# AutoMQ Strimzi Installation Script for AWS EKS
# Usage: ./install.sh [--check]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
NAMESPACE="${NAMESPACE:-automq}"
STRIMZI_VERSION="${STRIMZI_VERSION:-0.47.0}"
AUTOMQ_VERSION="${AUTOMQ_VERSION:-1.6.0-strimzi}"
KAFKA_VERSION="${KAFKA_VERSION:-3.9.0}"

# Minimum requirements
MIN_MEMORY_GB=16
SUPPORTED_INSTANCE_TYPES="r6i.large r6i.xlarge r6i.2xlarge r6in.large r6in.xlarge r6in.2xlarge"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
print_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
print_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }
print_step() {
    printf "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${CYAN}[STEP %s]${NC} %s\n" "$1" "$2"
    printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"
}
print_config() { printf "  ${CYAN}%-25s${NC} %s\n" "$1:" "$2"; }

print_header() {
    echo ""
    printf "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║${NC}       ${CYAN}AutoMQ Strimzi Deployment on AWS EKS${NC}                  ${BLUE}║${NC}\n"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    echo ""
}

check_prerequisites() {
    print_step "1/4" "Pre-flight Check"
    local has_error=0

    # Check kubectl
    printf "  Checking kubectl... "
    if ! command -v kubectl &> /dev/null; then
        printf "${RED}NOT FOUND${NC}\n"
        print_error "kubectl is not installed."
        has_error=1
    else
        printf "${GREEN}OK${NC}\n"
    fi

    # Check helm
    printf "  Checking helm... "
    if ! command -v helm &> /dev/null; then
        printf "${RED}NOT FOUND${NC}\n"
        print_error "helm is not installed."
        has_error=1
    else
        printf "${GREEN}OK${NC} ($(helm version --short 2>/dev/null))\n"
    fi

    # Check cluster connectivity
    printf "  Checking Kubernetes cluster... "
    if ! kubectl cluster-info &> /dev/null; then
        printf "${RED}NOT ACCESSIBLE${NC}\n"
        print_error "Cannot connect to Kubernetes cluster."
        has_error=1
    else
        local node_count
        node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
        printf "${GREEN}OK${NC} ($node_count nodes)\n"
    fi

    [ $has_error -eq 1 ] && { print_error "Prerequisites check failed."; exit 1; }

    # Check node instance types
    printf "  Checking node instance types... "
    local valid_nodes=0
    local total_nodes=0
    local invalid_nodes=""
    
    while IFS= read -r line; do
        node_name=$(echo "$line" | awk '{print $1}')
        instance_type=$(echo "$line" | awk '{print $2}')
        total_nodes=$((total_nodes + 1))
        
        if echo "$SUPPORTED_INSTANCE_TYPES" | grep -qw "$instance_type"; then
            valid_nodes=$((valid_nodes + 1))
        else
            invalid_nodes="$invalid_nodes\n    - $node_name ($instance_type)"
        fi
    done < <(kubectl get nodes -o custom-columns=NAME:.metadata.name,TYPE:.metadata.labels."node\.kubernetes\.io/instance-type" --no-headers 2>/dev/null)

    if [ $valid_nodes -ge 3 ]; then
        printf "${GREEN}OK${NC} ($valid_nodes/$total_nodes nodes with supported instance types)\n"
    else
        printf "${RED}INSUFFICIENT${NC}\n"
        print_error "Need at least 3 nodes with supported instance types."
        print_error "Supported types: $SUPPORTED_INSTANCE_TYPES"
        if [ -n "$invalid_nodes" ]; then
            print_error "Nodes with unsupported types:$invalid_nodes"
        fi
        print_error ""
        print_error "Please provision an EKS cluster with r6i.large or larger instances."
        print_error "See: byoc-examples/setup/kubernetes/aws/terraform/README.md"
        has_error=1
    fi

    # Check node memory
    printf "  Checking node memory... "
    local low_memory_nodes=""
    while IFS= read -r line; do
        node_name=$(echo "$line" | awk '{print $1}')
        allocatable_mem=$(echo "$line" | awk '{print $2}')
        
        # Convert to GB (handle Ki, Mi, Gi suffixes)
        if [[ "$allocatable_mem" == *"Ki" ]]; then
            mem_gb=$(echo "$allocatable_mem" | sed 's/Ki//' | awk '{printf "%.0f", $1/1024/1024}')
        elif [[ "$allocatable_mem" == *"Mi" ]]; then
            mem_gb=$(echo "$allocatable_mem" | sed 's/Mi//' | awk '{printf "%.0f", $1/1024}')
        elif [[ "$allocatable_mem" == *"Gi" ]]; then
            mem_gb=$(echo "$allocatable_mem" | sed 's/Gi//')
        else
            mem_gb=0
        fi
        
        if [ "$mem_gb" -lt "$MIN_MEMORY_GB" ] 2>/dev/null; then
            low_memory_nodes="$low_memory_nodes\n    - $node_name (${allocatable_mem})"
        fi
    done < <(kubectl get nodes -o custom-columns=NAME:.metadata.name,MEM:.status.allocatable.memory --no-headers 2>/dev/null)

    if [ -z "$low_memory_nodes" ]; then
        printf "${GREEN}OK${NC} (all nodes have >= ${MIN_MEMORY_GB}GB)\n"
    else
        printf "${YELLOW}WARNING${NC}\n"
        print_warn "Some nodes have less than ${MIN_MEMORY_GB}GB memory:$low_memory_nodes"
        print_warn "AutoMQ pods will not be scheduled on these nodes."
    fi

    # Check zone labels
    printf "  Checking zone labels... "
    local nodes_without_zone
    nodes_without_zone=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}' 2>/dev/null | grep -E "^\S+\s*$" | wc -l | tr -d ' ')

    if [ "$nodes_without_zone" -gt 0 ]; then
        printf "${YELLOW}MISSING${NC}\n"
        print_warn "Some nodes are missing topology.kubernetes.io/zone label"
    else
        printf "${GREEN}OK${NC}\n"
    fi

    [ $has_error -eq 1 ] && { print_error "Pre-flight check failed."; exit 1; }
    
    print_info "All pre-flight checks passed!"
}

install_strimzi() {
    print_step "2/4" "Installing Strimzi Operator"
    
    # Create namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
    
    if helm status automq-strimzi-operator -n "$NAMESPACE" &> /dev/null; then
        print_warn "Strimzi Operator already installed, upgrading..."
        helm upgrade automq-strimzi-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator \
            --version "$STRIMZI_VERSION" \
            --namespace "$NAMESPACE" \
            --values strimzi-values.yaml \
            --wait --timeout 5m > /dev/null
    else
        print_info "Installing Strimzi Operator..."
        helm install automq-strimzi-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator \
            --version "$STRIMZI_VERSION" \
            --namespace "$NAMESPACE" \
            --values strimzi-values.yaml \
            --wait --timeout 5m > /dev/null
    fi
    print_info "✓ Strimzi Operator installed"
}

check_s3_config() {
    print_step "3/4" "Checking S3 Configuration"
    
    # Check if automq-cluster.yaml has placeholder values
    if grep -q '\${OPS_BUCKET}\|\${DATA_BUCKET}\|\${AWS_REGION}' automq-cluster.yaml 2>/dev/null; then
        print_error "S3 bucket configuration not set in automq-cluster.yaml"
        echo ""
        echo "  Please configure your S3 buckets:"
        echo ""
        echo "  1. Create S3 buckets:"
        echo "     export AWS_REGION=us-east-1"
        echo "     export BUCKET_SUFFIX=\$(date +%s)"
        echo "     export DATA_BUCKET=\"automq-data-\${BUCKET_SUFFIX}\""
        echo "     export OPS_BUCKET=\"automq-ops-\${BUCKET_SUFFIX}\""
        echo "     aws s3 mb s3://\${DATA_BUCKET} --region \${AWS_REGION}"
        echo "     aws s3 mb s3://\${OPS_BUCKET} --region \${AWS_REGION}"
        echo ""
        echo "  2. Update automq-cluster.yaml:"
        echo "     sed -i.bak \\"
        echo "       -e \"s|\\\${OPS_BUCKET}|\${OPS_BUCKET}|g\" \\"
        echo "       -e \"s|\\\${DATA_BUCKET}|\${DATA_BUCKET}|g\" \\"
        echo "       -e \"s|\\\${AWS_REGION}|\${AWS_REGION}|g\" \\"
        echo "       automq-cluster.yaml"
        echo ""
        echo "  3. Re-run this script"
        echo ""
        exit 1
    fi
    
    print_info "✓ S3 configuration looks good"
}

install_automq() {
    print_step "4/4" "Installing AutoMQ Cluster"
    
    print_info "Deploying AutoMQ cluster (this may take a few minutes)..."
    kubectl apply -f automq-cluster.yaml -n "$NAMESPACE"
    
    # Wait for cluster to be ready
    print_info "Waiting for AutoMQ pods to be ready..."
    
    MAX_RETRIES=60
    RETRY_COUNT=0
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        READY_PODS=$(kubectl get pods -n "$NAMESPACE" -l strimzi.io/cluster=my-cluster -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | grep -c "true" || echo "0")
        TOTAL_PODS=$(kubectl get pods -n "$NAMESPACE" -l strimzi.io/cluster=my-cluster --no-headers 2>/dev/null | wc -l | tr -d ' ')
        
        if [ "$READY_PODS" -ge 3 ] && [ "$READY_PODS" -eq "$TOTAL_PODS" ]; then
            echo ""
            print_info "✓ AutoMQ cluster is ready ($READY_PODS pods running)"
            break
        fi
        
        RETRY_COUNT=$((RETRY_COUNT + 1))
        printf "\r  Waiting for pods... (%d/%d) - %d/%d pods ready" "$RETRY_COUNT" "$MAX_RETRIES" "$READY_PODS" "$TOTAL_PODS"
        sleep 5
    done
    
    echo ""
    
    if [ "$READY_PODS" -lt 3 ]; then
        print_warn "Not all pods are ready yet. Check status with: kubectl get pods -n $NAMESPACE"
        print_warn "Check logs with: kubectl logs -l strimzi.io/cluster=my-cluster -n $NAMESPACE"
    fi
}

print_summary() {
    printf "\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║${NC}                  ${GREEN}Installation Complete!${NC}                      ${BLUE}║${NC}\n"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\n\n"
    
    echo "  Namespace: $NAMESPACE"
    echo "  Bootstrap Server: my-cluster-kafka-bootstrap.$NAMESPACE.svc.cluster.local:9092"
    echo ""
    echo "  Next Steps:"
    echo "    ./verify.sh  - Test the cluster"
    echo "    ./cleanup.sh - Remove the cluster"
    echo ""
    echo "  Quick Test:"
    echo "    kubectl exec -it -n $NAMESPACE my-cluster-controller-0 -- \\"
    echo "      /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list"
    echo ""
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --check    Run pre-flight checks only (do not install)"
    echo "  --help     Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  NAMESPACE       Kubernetes namespace (default: automq)"
    echo "  STRIMZI_VERSION Strimzi version (default: 0.47.0)"
    echo ""
    echo "Prerequisites:"
    echo "  - AWS EKS cluster with r6i.large or larger nodes"
    echo "  - kubectl and helm installed"
    echo "  - S3 buckets created and configured in automq-cluster.yaml"
    echo ""
    echo "For EKS cluster setup, see:"
    echo "  byoc-examples/setup/kubernetes/aws/terraform/README.md"
}

main() {
    # Parse arguments
    case "${1:-}" in
        --check)
            print_header
            check_prerequisites
            echo ""
            print_info "Pre-flight check completed successfully!"
            print_info "Run './install.sh' to proceed with installation."
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
    esac

    print_header
    check_prerequisites
    install_strimzi
    check_s3_config
    install_automq
    print_summary
}

main "$@"
