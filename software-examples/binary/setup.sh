#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
AUTOMQ_VERSION="5.3.4"
AUTOMQ_DOWNLOAD_URL="https://go.automq.com/software_${AUTOMQ_VERSION}"
AUTOMQ_PACKAGE_NAME="automq-enterprise-${AUTOMQ_VERSION}.tgz"
AUTOMQ_DIR_NAME="automq-kafka-enterprise_${AUTOMQ_VERSION}"
MINIO_USER="admin"
MINIO_PASSWORD="automq_demo_secret"
MINIO_ENDPOINT="http://127.0.0.1:9000"
CLUSTER_NAME="local-demo"

print_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

print_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

print_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

print_header() {
    echo ""
    echo "=============================================="
    echo " AutoMQ Binary Deployment Setup"
    echo "=============================================="
    echo ""
}

# Pre-flight checks
check_prerequisites() {
    print_info "Checking prerequisites..."
    local has_error=0

    # Check Java
    if ! command -v java &> /dev/null; then
        print_error "Java is not installed. Please install Java 17 or later."
        print_info "  Installation guide: https://adoptium.net/"
        has_error=1
    else
        local java_version
        java_version=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | cut -d'.' -f1)
        if [ "$java_version" -lt 17 ] 2>/dev/null; then
            print_error "Java 17 or later is required. Current version: $java_version"
            has_error=1
        else
            print_info "✓ Java found: $(java -version 2>&1 | head -1)"
        fi
    fi

    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        print_info "  Installation guide: https://docs.docker.com/get-docker/"
        has_error=1
    else
        if ! docker info &> /dev/null; then
            print_error "Docker daemon is not running. Please start Docker."
            has_error=1
        else
            print_info "✓ Docker found: $(docker --version)"
        fi
    fi

    # Check Docker Compose
    if command -v docker-compose &> /dev/null; then
        print_info "✓ Docker Compose found: $(docker-compose --version)"
    elif docker compose version &> /dev/null; then
        print_info "✓ Docker Compose found: $(docker compose version)"
    else
        print_error "Docker Compose is not installed."
        has_error=1
    fi

    # Check curl
    if ! command -v curl &> /dev/null; then
        print_error "curl is not installed. Please install curl first."
        has_error=1
    else
        print_info "✓ curl found"
    fi

    if [ $has_error -eq 1 ]; then
        echo ""
        print_error "Prerequisites check failed. Please resolve the issues above and try again."
        exit 1
    fi

    print_info "All prerequisites satisfied!"
    echo ""
}

# Download AutoMQ package
download_automq() {
    if [ -f "$AUTOMQ_PACKAGE_NAME" ]; then
        print_info "Package $AUTOMQ_PACKAGE_NAME already exists, skipping download."
    else
        print_info "Downloading AutoMQ ${AUTOMQ_VERSION}..."
        curl -L -o "$AUTOMQ_PACKAGE_NAME" "$AUTOMQ_DOWNLOAD_URL"
        print_info "✓ Downloaded $AUTOMQ_PACKAGE_NAME"
    fi
    
    # Extract if not already extracted
    if [ ! -d "$AUTOMQ_DIR_NAME" ]; then
        print_info "Extracting $AUTOMQ_PACKAGE_NAME..."
        tar -xzf "$AUTOMQ_PACKAGE_NAME"
        print_info "✓ Extracted to $AUTOMQ_DIR_NAME"
    else
        print_info "Directory $AUTOMQ_DIR_NAME already exists, skipping extraction."
    fi
}

# Create MinIO docker-compose file
create_minio_compose() {
    print_info "Creating MinIO configuration..."
    
    mkdir -p minio
    
    cat <<'EOF' > minio/docker-compose.yml
services:
  minio:
    image: minio/minio:latest
    container_name: automq-minio
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      MINIO_ROOT_USER: admin
      MINIO_ROOT_PASSWORD: automq_demo_secret
    command: server /data --console-address ":9001"
    volumes:
      - minio-data:/data
    healthcheck:
      test: ["CMD", "mc", "ready", "local"]
      interval: 5s
      timeout: 5s
      retries: 5

  minio-init:
    image: minio/mc:latest
    container_name: automq-minio-init
    depends_on:
      minio:
        condition: service_healthy
    entrypoint: >
      /bin/sh -c "
      mc alias set local http://minio:9000 admin automq_demo_secret;
      mc mb local/automq-data --ignore-existing;
      mc mb local/automq-ops --ignore-existing;
      echo 'Buckets created successfully';
      "

volumes:
  minio-data:
EOF

    print_info "✓ Created minio/docker-compose.yml"
}

# Create cluster project using automq-cli
create_cluster_project() {
    print_info "Creating AutoMQ cluster project..."
    
    pushd "$AUTOMQ_DIR_NAME" > /dev/null
    
    # Create cluster project
    bin/automq-cli.sh cluster create "$CLUSTER_NAME"
    
    popd > /dev/null
    
    print_info "✓ Created cluster project: $CLUSTER_NAME"
}

# Generate topo.yaml for local 3-node cluster
generate_topo_yaml() {
    print_info "Generating cluster topology configuration..."
    
    local topo_file="$AUTOMQ_DIR_NAME/clusters/$CLUSTER_NAME/topo.yaml"
    
    cat <<EOF > "$topo_file"
global:
  clusterId: ''
  # Local MinIO configuration for quick start
  # For production, replace with your cloud object storage (AWS S3, Azure Blob, etc.)
  config: |
    s3.data.buckets=0@s3://automq-data?region=us-east-1&endpoint=${MINIO_ENDPOINT}&pathStyle=true
    s3.ops.buckets=0@s3://automq-ops?region=us-east-1&endpoint=${MINIO_ENDPOINT}&pathStyle=true
    s3.wal.path=0@s3://automq-data?region=us-east-1&endpoint=${MINIO_ENDPOINT}&pathStyle=true
  envs:
    - name: KAFKA_S3_ACCESS_KEY
      value: '${MINIO_USER}'
    - name: KAFKA_S3_SECRET_KEY
      value: '${MINIO_PASSWORD}'
    - name: KAFKA_HEAP_OPTS
      value: '-Xmx2g -Xms2g'
controllers:
  # 3-node cluster configuration
  # For local pseudo-cluster: change hosts to 127.0.0.1 and manually modify ports in startup commands
  - host: 127.0.0.1
    nodeId: 0
  - host: 127.0.0.1
    nodeId: 1
  - host: 127.0.0.1
    nodeId: 2
brokers: []
EOF

    print_info "✓ Generated $topo_file"
}

# Print next steps
print_next_steps() {
    echo ""
    echo "=============================================="
    echo " Setup Complete!"
    echo "=============================================="
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Start MinIO:"
    echo "   docker compose -f minio/docker-compose.yml up -d"
    echo ""
    echo "2. Generate startup commands:"
    echo "   cd ${AUTOMQ_DIR_NAME}"
    echo "   bin/automq-cli.sh cluster deploy --dry-run clusters/${CLUSTER_NAME}"
    echo ""
    echo "3. Start AutoMQ nodes:"
    echo "   The above command outputs startup commands for each node."
    echo ""
    echo "   IMPORTANT: For local pseudo-cluster (all nodes on same machine),"
    echo "   you need to manually modify the ports in each command:"
    echo "   - Node 0: broker port 9092, controller port 19092"
    echo "   - Node 1: broker port 9093, controller port 19093"
    echo "   - Node 2: broker port 9094, controller port 19094"
    echo ""
    echo "   Modify these parameters in each startup command:"
    echo "   --override listeners=PLAINTEXT://127.0.0.1:<broker_port>,CONTROLLER://127.0.0.1:<controller_port>"
    echo "   --override advertised.listeners=PLAINTEXT://127.0.0.1:<broker_port>"
    echo "   --override controller.quorum.voters=0@127.0.0.1:19092,1@127.0.0.1:19093,2@127.0.0.1:19094"
    echo ""
    echo "   Run each modified command in a separate terminal."
    echo ""
    echo "4. Verify installation:"
    echo "   cd .. && ./verify.sh"
    echo ""
    echo "5. Cleanup:"
    echo "   cd .. && ./cleanup.sh"
    echo ""
    echo "MinIO Console: http://localhost:9001"
    echo "  Username: ${MINIO_USER}"
    echo "  Password: ${MINIO_PASSWORD}"
    echo ""
}

# Main
main() {
    print_header
    check_prerequisites
    download_automq
    create_minio_compose
    create_cluster_project
    generate_topo_yaml
    print_next_steps
}

main "$@"
