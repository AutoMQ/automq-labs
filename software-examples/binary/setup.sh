#!/bin/bash
# AutoMQ Software Binary Deployment Setup Script
# Supports: curl -sSL https://raw.githubusercontent.com/AutoMQ/automq-labs/main/software-examples/binary/setup.sh | bash

set -e

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

print_info() { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
print_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
print_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

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

    if ! command -v curl &> /dev/null; then
        print_error "curl is not installed."
        has_error=1
    else
        print_info "✓ curl found"
    fi

    if ! command -v java &> /dev/null; then
        print_error "Java is not installed. Please install Java 17 or later."
        has_error=1
    else
        local java_version
        java_version=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | cut -d'.' -f1)
        if [ "$java_version" -lt 17 ] 2>/dev/null; then
            print_error "Java 17 or later is required."
            has_error=1
        else
            print_info "✓ Java found"
        fi
    fi

    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed."
        has_error=1
    else
        if ! docker info &> /dev/null; then
            print_error "Docker daemon is not running."
            has_error=1
        else
            print_info "✓ Docker found"
        fi
    fi

    if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
        print_info "✓ Docker Compose found"
    else
        print_error "Docker Compose is not installed."
        has_error=1
    fi

    [ $has_error -eq 1 ] && { print_error "Prerequisites check failed."; exit 1; }
    print_info "All prerequisites satisfied!"
    echo ""
}

generate_helper_scripts() {
    print_info "Generating helper scripts..."

    # Generate format-storage.sh
    cat > format-storage.sh << 'FORMAT_EOF'
#!/bin/bash
set -e
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
AUTOMQ_DIR="automq-kafka-enterprise_5.3.4"
print_info() { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
print_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

echo ""
echo "=============================================="
echo " AutoMQ Storage Format"
echo "=============================================="
echo ""

[ ! -d "$AUTOMQ_DIR" ] && { print_error "AutoMQ directory not found. Run setup.sh first."; exit 1; }

print_info "Generating cluster ID..."
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
echo ""
echo "Now start the cluster in 3 separate terminals:"
echo ""
echo "# Terminal 1"
echo "cd ${AUTOMQ_DIR} && export KAFKA_S3_ACCESS_KEY=admin && export KAFKA_S3_SECRET_KEY=automq_demo_secret && export KAFKA_HEAP_OPTS=\"-Xmx2g -Xms2g\" && bin/kafka-server-start.sh config/kraft/node0.properties"
echo ""
echo "# Terminal 2"
echo "cd ${AUTOMQ_DIR} && export KAFKA_S3_ACCESS_KEY=admin && export KAFKA_S3_SECRET_KEY=automq_demo_secret && export KAFKA_HEAP_OPTS=\"-Xmx2g -Xms2g\" && bin/kafka-server-start.sh config/kraft/node1.properties"
echo ""
echo "# Terminal 3"
echo "cd ${AUTOMQ_DIR} && export KAFKA_S3_ACCESS_KEY=admin && export KAFKA_S3_SECRET_KEY=automq_demo_secret && export KAFKA_HEAP_OPTS=\"-Xmx2g -Xms2g\" && bin/kafka-server-start.sh config/kraft/node2.properties"
echo ""
FORMAT_EOF
    chmod +x format-storage.sh
    print_info "✓ Generated format-storage.sh"

    # Generate verify.sh
    cat > verify.sh << 'VERIFY_EOF'
#!/bin/bash
set -e
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
AUTOMQ_DIR="automq-kafka-enterprise_5.3.4"
BOOTSTRAP_SERVER="localhost:9092"
print_info() { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
print_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

echo ""
echo "=============================================="
echo " AutoMQ Installation Verification"
echo "=============================================="
echo ""

[ ! -d "$AUTOMQ_DIR" ] && { print_error "AutoMQ directory not found."; exit 1; }

print_info "Checking broker connectivity..."
if ! "$AUTOMQ_DIR/bin/kafka-broker-api-versions.sh" --bootstrap-server "$BOOTSTRAP_SERVER" > /dev/null 2>&1; then
    print_error "Cannot connect to broker at $BOOTSTRAP_SERVER"
    exit 1
fi
print_info "✓ Broker is accessible"

print_info "Creating test topic..."
"$AUTOMQ_DIR/bin/kafka-topics.sh" --create --topic test-topic --partitions 3 --replication-factor 1 --bootstrap-server "$BOOTSTRAP_SERVER" --if-not-exists 2>/dev/null || true
print_info "✓ Test topic created"

print_info "Listing topics..."
echo ""
"$AUTOMQ_DIR/bin/kafka-topics.sh" --list --bootstrap-server "$BOOTSTRAP_SERVER"
echo ""

echo "=============================================="
echo " Verification Complete!"
echo "=============================================="
echo ""
print_info "AutoMQ cluster is running and accessible."
echo ""
echo "Bootstrap servers: localhost:9092, localhost:9093, localhost:9094"
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
AUTOMQ_DIR="automq-kafka-enterprise_5.3.4"
print_info() { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
print_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }

echo ""
echo "=============================================="
echo " AutoMQ Cleanup"
echo "=============================================="
echo ""

[ "$1" != "-y" ] && [ "$1" != "--yes" ] && {
    printf "This will stop AutoMQ and MinIO, and remove data. Continue? [y/N] "
    read -r REPLY
    [[ ! "$REPLY" =~ ^[Yy] ]] && { print_info "Cleanup cancelled."; exit 0; }
}
echo ""

print_info "Stopping AutoMQ nodes..."
[ -d "$AUTOMQ_DIR" ] && "$AUTOMQ_DIR/bin/kafka-server-stop.sh" 2>/dev/null || true
sleep 2
print_info "✓ AutoMQ nodes stopped"

print_info "Stopping MinIO..."
[ -f "minio/docker-compose.yml" ] && docker compose -f minio/docker-compose.yml down -v 2>/dev/null || true
print_info "✓ MinIO stopped"

print_info "Removing data directories..."
rm -rf /tmp/automq-data-* 2>/dev/null || true
print_info "✓ Data directories removed"

echo ""
echo "=============================================="
echo " Cleanup Complete!"
echo "=============================================="
echo ""
CLEANUP_EOF
    chmod +x cleanup.sh
    print_info "✓ Generated cleanup.sh"
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
    
    cat > minio/docker-compose.yml << 'MINIO_EOF'
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
MINIO_EOF
    print_info "✓ Created minio/docker-compose.yml"
}

generate_node_configs() {
    print_info "Generating node configuration files..."
    
    local config_dir="$AUTOMQ_DIR_NAME/config/kraft"
    mkdir -p "$config_dir"
    
    local s3_config="s3.data.buckets=0@s3://automq-data?region=us-east-1&endpoint=${MINIO_ENDPOINT}&pathStyle=true
s3.ops.buckets=0@s3://automq-ops?region=us-east-1&endpoint=${MINIO_ENDPOINT}&pathStyle=true
s3.wal.path=0@s3://automq-data?region=us-east-1&endpoint=${MINIO_ENDPOINT}&pathStyle=true"

    for i in 0 1 2; do
        local port=$((9092 + i))
        local ctrl_port=$((19092 + i))
        cat > "$config_dir/node${i}.properties" << EOF
node.id=${i}
process.roles=broker,controller
listeners=PLAINTEXT://127.0.0.1:${port},CONTROLLER://127.0.0.1:${ctrl_port}
advertised.listeners=PLAINTEXT://127.0.0.1:${port}
controller.listener.names=CONTROLLER
controller.quorum.voters=0@127.0.0.1:19092,1@127.0.0.1:19093,2@127.0.0.1:19094
inter.broker.listener.name=PLAINTEXT
log.dirs=/tmp/automq-data-${i}
${s3_config}
num.partitions=1
default.replication.factor=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
EOF
    done
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
    echo "3. Start AutoMQ nodes (in 3 separate terminals)"
    echo ""
    echo "4. Verify installation:"
    echo "   ./verify.sh"
    echo ""
    echo "MinIO Console: http://localhost:9001"
    echo "  Username: ${MINIO_USER}"
    echo "  Password: ${MINIO_PASSWORD}"
    echo ""
}

main() {
    print_header
    check_prerequisites
    generate_helper_scripts
    download_automq
    create_minio_compose
    generate_node_configs
    print_next_steps
}

main "$@"
