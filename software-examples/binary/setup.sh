#!/bin/bash
# AutoMQ Software Binary Deployment Setup Script
# Supports: curl -sSL https://raw.githubusercontent.com/AutoMQ/automq-examples/main/software-examples/binary/setup.sh | bash

set -e

# GitHub raw URL base
GITHUB_RAW_BASE="https://raw.githubusercontent.com/AutoMQ/automq-examples/main/software-examples/binary"

# Configuration
AUTOMQ_VERSION="5.3.4"
AUTOMQ_DOWNLOAD_URL="https://go.automq.com/software_${AUTOMQ_VERSION}"
AUTOMQ_PACKAGE_NAME="automq-enterprise-${AUTOMQ_VERSION}.tgz"
AUTOMQ_DIR_NAME="automq-kafka-enterprise_${AUTOMQ_VERSION}"
MINIO_USER="admin"
MINIO_PASSWORD="automq_demo_secret"
MINIO_ENDPOINT="http://127.0.0.1:9000"

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

check_prerequisites() {
    print_info "Checking prerequisites..."
    local has_error=0

    # Check curl
    if ! command -v curl &> /dev/null; then
        print_error "curl is not installed."
        has_error=1
    else
        print_info "✓ curl found"
    fi

    # Check Java
    if ! command -v java &> /dev/null; then
        print_error "Java is not installed. Please install Java 17 or later."
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
        print_error "Docker is not installed."
        has_error=1
    else
        if ! docker info &> /dev/null; then
            print_error "Docker daemon is not running."
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

    if [ $has_error -eq 1 ]; then
        echo ""
        print_error "Prerequisites check failed."
        exit 1
    fi

    print_info "All prerequisites satisfied!"
    echo ""
}

download_helper_scripts() {
    print_info "Downloading helper scripts..."
    
    curl -sSL -o format-storage.sh "${GITHUB_RAW_BASE}/format-storage.sh"
    chmod +x format-storage.sh
    print_info "✓ Downloaded format-storage.sh"

    curl -sSL -o verify.sh "${GITHUB_RAW_BASE}/verify.sh"
    chmod +x verify.sh
    print_info "✓ Downloaded verify.sh"

    curl -sSL -o cleanup.sh "${GITHUB_RAW_BASE}/cleanup.sh"
    chmod +x cleanup.sh
    print_info "✓ Downloaded cleanup.sh"
    
    echo ""
}

download_automq() {
    if [ -f "$AUTOMQ_PACKAGE_NAME" ]; then
        print_info "Package $AUTOMQ_PACKAGE_NAME already exists, skipping download."
    else
        print_info "Downloading AutoMQ ${AUTOMQ_VERSION}..."
        curl -L -o "$AUTOMQ_PACKAGE_NAME" "$AUTOMQ_DOWNLOAD_URL"
        print_info "✓ Downloaded $AUTOMQ_PACKAGE_NAME"
    fi
    
    if [ ! -d "$AUTOMQ_DIR_NAME" ]; then
        print_info "Extracting $AUTOMQ_PACKAGE_NAME..."
        tar -xzf "$AUTOMQ_PACKAGE_NAME"
        print_info "✓ Extracted to $AUTOMQ_DIR_NAME"
    else
        print_info "Directory $AUTOMQ_DIR_NAME already exists, skipping extraction."
    fi
}

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

generate_node_configs() {
    print_info "Generating node configuration files..."
    
    local config_dir="$AUTOMQ_DIR_NAME/config/kraft"
    mkdir -p "$config_dir"
    
    # S3 common config
    local s3_config="s3.data.buckets=0@s3://automq-data?region=us-east-1&endpoint=${MINIO_ENDPOINT}&pathStyle=true
s3.ops.buckets=0@s3://automq-ops?region=us-east-1&endpoint=${MINIO_ENDPOINT}&pathStyle=true
s3.wal.path=0@s3://automq-data?region=us-east-1&endpoint=${MINIO_ENDPOINT}&pathStyle=true"

    # Node 0 config
    cat <<EOF > "$config_dir/node0.properties"
# Node 0 Configuration
node.id=0
process.roles=broker,controller
listeners=PLAINTEXT://127.0.0.1:9092,CONTROLLER://127.0.0.1:19092
advertised.listeners=PLAINTEXT://127.0.0.1:9092
controller.listener.names=CONTROLLER
controller.quorum.voters=0@127.0.0.1:19092,1@127.0.0.1:19093,2@127.0.0.1:19094
inter.broker.listener.name=PLAINTEXT

# Log directories
log.dirs=/tmp/automq-data-0

# S3 Configuration
${s3_config}

# Default settings
num.partitions=1
default.replication.factor=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
EOF

    # Node 1 config
    cat <<EOF > "$config_dir/node1.properties"
# Node 1 Configuration
node.id=1
process.roles=broker,controller
listeners=PLAINTEXT://127.0.0.1:9093,CONTROLLER://127.0.0.1:19093
advertised.listeners=PLAINTEXT://127.0.0.1:9093
controller.listener.names=CONTROLLER
controller.quorum.voters=0@127.0.0.1:19092,1@127.0.0.1:19093,2@127.0.0.1:19094
inter.broker.listener.name=PLAINTEXT

# Log directories
log.dirs=/tmp/automq-data-1

# S3 Configuration
${s3_config}

# Default settings
num.partitions=1
default.replication.factor=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
EOF

    # Node 2 config
    cat <<EOF > "$config_dir/node2.properties"
# Node 2 Configuration
node.id=2
process.roles=broker,controller
listeners=PLAINTEXT://127.0.0.1:9094,CONTROLLER://127.0.0.1:19094
advertised.listeners=PLAINTEXT://127.0.0.1:9094
controller.listener.names=CONTROLLER
controller.quorum.voters=0@127.0.0.1:19092,1@127.0.0.1:19093,2@127.0.0.1:19094
inter.broker.listener.name=PLAINTEXT

# Log directories
log.dirs=/tmp/automq-data-2

# S3 Configuration
${s3_config}

# Default settings
num.partitions=1
default.replication.factor=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
EOF

    print_info "✓ Generated node0.properties, node1.properties, node2.properties"
}

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
    echo "2. Format storage (run once):"
    echo "   ./format-storage.sh"
    echo ""
    echo "3. Start AutoMQ nodes (in 3 separate terminals):"
    echo ""
    echo "   # Terminal 1 - Node 0"
    echo "   cd ${AUTOMQ_DIR_NAME}"
    echo "   export KAFKA_S3_ACCESS_KEY=admin"
    echo "   export KAFKA_S3_SECRET_KEY=automq_demo_secret"
    echo "   export KAFKA_HEAP_OPTS=\"-Xmx2g -Xms2g\""
    echo "   bin/kafka-server-start.sh config/kraft/node0.properties"
    echo ""
    echo "   # Terminal 2 - Node 1"
    echo "   cd ${AUTOMQ_DIR_NAME}"
    echo "   export KAFKA_S3_ACCESS_KEY=admin"
    echo "   export KAFKA_S3_SECRET_KEY=automq_demo_secret"
    echo "   export KAFKA_HEAP_OPTS=\"-Xmx2g -Xms2g\""
    echo "   bin/kafka-server-start.sh config/kraft/node1.properties"
    echo ""
    echo "   # Terminal 3 - Node 2"
    echo "   cd ${AUTOMQ_DIR_NAME}"
    echo "   export KAFKA_S3_ACCESS_KEY=admin"
    echo "   export KAFKA_S3_SECRET_KEY=automq_demo_secret"
    echo "   export KAFKA_HEAP_OPTS=\"-Xmx2g -Xms2g\""
    echo "   bin/kafka-server-start.sh config/kraft/node2.properties"
    echo ""
    echo "4. Verify installation:"
    echo "   ./verify.sh"
    echo ""
    echo "5. Stop cluster:"
    echo "   cd ${AUTOMQ_DIR_NAME} && bin/kafka-server-stop.sh"
    echo ""
    echo "MinIO Console: http://localhost:9001"
    echo "  Username: ${MINIO_USER}"
    echo "  Password: ${MINIO_PASSWORD}"
    echo ""
}

main() {
    print_header
    check_prerequisites
    download_helper_scripts
    download_automq
    create_minio_compose
    generate_node_configs
    print_next_steps
}

main "$@"
