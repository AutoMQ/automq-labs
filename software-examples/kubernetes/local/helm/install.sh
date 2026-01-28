#!/bin/bash
# AutoMQ Software Kubernetes Helm Installation Script
# Supports: curl -sSL https://raw.githubusercontent.com/AutoMQ/automq-labs/main/software-examples/kubernetes/local/helm/install.sh | bash

set -e

# Configuration
AUTOMQ_VERSION="5.3.4"
MINIO_USER="admin"
MINIO_PASSWORD="automq_demo_secret"

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
    printf "${BLUE}║${NC}     ${CYAN}AutoMQ Local Deployment - One-Click Installation${NC}        ${BLUE}║${NC}\n"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    echo ""
}

print_summary() {
    printf "\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║${NC}                  ${GREEN}Installation Complete!${NC}                      ${BLUE}║${NC}\n"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\n\n"
}

check_prerequisites() {
    print_step "1/6" "Checking Prerequisites"
    local has_error=0

    printf "  Checking kubectl... "
    if ! command -v kubectl &> /dev/null; then
        printf "${RED}NOT FOUND${NC}\n"
        print_error "kubectl is not installed."
        has_error=1
    else
        printf "${GREEN}OK${NC}\n"
    fi

    printf "  Checking helm... "
    if ! command -v helm &> /dev/null; then
        printf "${RED}NOT FOUND${NC}\n"
        print_error "helm is not installed."
        has_error=1
    else
        printf "${GREEN}OK${NC} ($(helm version --short 2>/dev/null))\n"
    fi

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
    print_info "All prerequisites satisfied!"
}

generate_scripts() {
    print_step "2/6" "Generating Helper Scripts"

    # Generate verify.sh
    cat > verify.sh << 'VERIFY_EOF'
#!/bin/bash
set -e
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
print_info() { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
print_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

echo ""
echo "=============================================="
echo " AutoMQ Installation Verification"
echo "=============================================="
echo ""

print_info "Checking AutoMQ pods status..."
ready_pods=$(kubectl get pods -l app.kubernetes.io/name=automq-enterprise --no-headers 2>/dev/null | grep -c "Running" || echo "0")
total_pods=$(kubectl get pods -l app.kubernetes.io/name=automq-enterprise --no-headers 2>/dev/null | wc -l | tr -d ' ')
[ "$total_pods" -eq 0 ] && { print_error "No AutoMQ pods found."; exit 1; }
echo ""
kubectl get pods -l app.kubernetes.io/name=automq-enterprise
echo ""
[ "$ready_pods" -ne "$total_pods" ] && kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=automq-enterprise --timeout=300s
print_info "✓ All AutoMQ pods are running"

print_info "Creating test topic..."
kubectl run kafka-client-test --rm -it --restart=Never --image=confluentinc/cp-kafka:latest --command -- \
    kafka-topics --bootstrap-server automq-automq-enterprise-controller-headless:9092 \
    --create --topic test-topic --partitions 3 --replication-factor 1 --if-not-exists
print_info "✓ Test topic created"

print_info "Listing topics..."
kubectl run kafka-client-list --rm -it --restart=Never --image=confluentinc/cp-kafka:latest --command -- \
    kafka-topics --bootstrap-server automq-automq-enterprise-controller-headless:9092 --list

echo ""
echo "=============================================="
echo " Verification Complete!"
echo "=============================================="
echo ""
VERIFY_EOF
    chmod +x verify.sh
    print_info "✓ Generated verify.sh"

    # Generate cleanup.sh
    cat > cleanup.sh << 'CLEANUP_EOF'
#!/bin/bash
set -e
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
print_info() { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
print_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }

echo ""
echo "=============================================="
echo " AutoMQ Cleanup"
echo "=============================================="
echo ""

printf "This will remove AutoMQ and MinIO. Continue? [y/N] "
read -r REPLY
[[ ! "$REPLY" =~ ^[Yy] ]] && { print_info "Cleanup cancelled."; exit 0; }
echo ""

print_info "Removing AutoMQ..."
helm status automq &> /dev/null && helm uninstall automq && print_info "✓ AutoMQ removed" || print_warn "AutoMQ not found"
kubectl delete pvc -l app.kubernetes.io/name=automq-enterprise 2>/dev/null || true

print_info "Removing MinIO..."
helm status minio &> /dev/null && helm uninstall minio && print_info "✓ MinIO removed" || print_warn "MinIO not found"
kubectl delete pvc -l app=minio 2>/dev/null || true

[ -f "automq-values.yaml" ] && rm -f automq-values.yaml && print_info "✓ automq-values.yaml removed"

echo ""
echo "=============================================="
echo " Cleanup Complete!"
echo "=============================================="
echo ""
CLEANUP_EOF
    chmod +x cleanup.sh
    print_info "✓ Generated cleanup.sh"
}

generate_values() {
    print_step "3/6" "Generating Configuration"
    
    local arch=$(uname -m)
    case $arch in
        arm64|aarch64) NODE_ARCH="arm64" ;;
        *) NODE_ARCH="amd64" ;;
    esac
    
    print_info "Detected CPU architecture: $NODE_ARCH"
    
    cat > automq-values.yaml << EOF
global:
  automqInstanceId: "automq-demo-cluster"
  cloudProvider:
    name: "noop"
    credentials: "static://?accessKey=admin&secretKey=automq_demo_secret"
  nodeAffinities:
    - key: "kubernetes.io/arch"
      values:
        - "${NODE_ARCH}"
  config: |
    s3.ops.buckets=0@s3://automq-ops?region=us-east-1&endpoint=http://minio.default.svc.cluster.local:9000&pathStyle=true
    s3.data.buckets=0@s3://automq-data?region=us-east-1&endpoint=http://minio.default.svc.cluster.local:9000&pathStyle=true
    s3.wal.path=0@s3://automq-data?region=us-east-1&endpoint=http://minio.default.svc.cluster.local:9000&pathStyle=true

controller:
  replicas: 3
  resources:
    requests:
      cpu: "1000m"
      memory: "2Gi"
    limits:
      cpu: "2000m"
      memory: "4Gi"
  env:
    - name: "KAFKA_S3_ACCESS_KEY"
      value: "admin"
    - name: "KAFKA_S3_SECRET_KEY"
      value: "automq_demo_secret"
    - name: "KAFKA_HEAP_OPTS"
      value: "-Xmx2g -Xms2g"
  persistence:
    wal:
      enabled: false

broker:
  replicas: 0
  env:
    - name: "KAFKA_S3_ACCESS_KEY"
      value: "admin"
    - name: "KAFKA_S3_SECRET_KEY"
      value: "automq_demo_secret"
  persistence:
    wal:
      enabled: false
EOF
    print_info "✓ Generated automq-values.yaml"
    print_config "Architecture" "$NODE_ARCH"
    print_config "Controller Replicas" "3"
}

install_minio() {
    print_step "4/6" "Installing MinIO"
    
    helm repo add minio https://charts.min.io/ > /dev/null 2>&1 || true
    helm repo update > /dev/null 2>&1
    
    if helm status minio &> /dev/null; then
        print_warn "MinIO already installed, skipping..."
        return
    fi
    
    print_info "Installing MinIO..."
    helm install minio minio/minio \
        --set rootUser=admin \
        --set rootPassword=automq_demo_secret \
        --set "buckets[0].name=automq-data,buckets[0].policy=none,buckets[0].purge=false" \
        --set "buckets[1].name=automq-ops,buckets[1].policy=none,buckets[1].purge=false" \
        --set mode=standalone \
        --set service.type=ClusterIP \
        --set persistence.enabled=false \
        --set resources.requests.memory=512Mi \
        --set resources.requests.cpu=250m \
        --set resources.limits.memory=2Gi \
        --set resources.limits.cpu=2 \
        --wait --timeout 5m > /dev/null
    print_info "✓ MinIO installed"
}

install_automq() {
    print_step "5/6" "Installing AutoMQ"
    
    if helm status automq &> /dev/null; then
        print_warn "AutoMQ already installed, skipping..."
        return
    fi
    
    print_info "Installing AutoMQ (this may take a few minutes)..."
    helm install automq oci://automq.azurecr.io/helm/automq-enterprise-chart \
        --version "$AUTOMQ_VERSION" \
        -f automq-values.yaml \
        --wait --timeout 10m > /dev/null
    print_info "✓ AutoMQ installed"
}

verify_installation() {
    print_step "6/6" "Verifying Installation"
    
    print_info "Checking pod status..."
    echo ""
    kubectl get pods -l app.kubernetes.io/name=automq-enterprise
    echo ""
    
    ready_pods=$(kubectl get pods -l app.kubernetes.io/name=automq-enterprise --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    total_pods=$(kubectl get pods -l app.kubernetes.io/name=automq-enterprise --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    [ "$ready_pods" -ne "$total_pods" ] && kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=automq-enterprise --timeout=300s
    print_info "✓ All AutoMQ pods are running"
}

print_final_summary() {
    print_summary
    echo "  Bootstrap Server: automq-automq-enterprise-controller-headless:9092"
    echo ""
    echo "  Next Steps:"
    echo "    ./verify.sh  - Test the cluster"
    echo "    ./cleanup.sh - Remove the cluster"
    echo ""
}

main() {
    print_header
    check_prerequisites
    generate_scripts
    generate_values
    install_minio
    install_automq
    verify_installation
    print_final_summary
}

main "$@"
