#!/bin/bash
# AutoMQ Software Docker Compose Installation Script
# Supports: curl -sSL https://raw.githubusercontent.com/AutoMQ/automq-labs/main/software-examples/docker-compose/install.sh | bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         AutoMQ Software - Docker Compose Setup               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Prerequisites Check
print_step "Step 1/5: Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi
print_success "Docker is installed"

if ! docker info &> /dev/null; then
    print_error "Docker daemon is not running. Please start Docker."
    exit 1
fi
print_success "Docker daemon is running"

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    print_error "Docker Compose is not installed. Please install Docker Compose."
    exit 1
fi
print_success "Docker Compose is available"

echo ""

# Step 2: Generate configuration files
print_step "Step 2/5: Generating configuration files..."

# Generate docker-compose.yaml
cat > docker-compose.yaml << 'DOCKER_COMPOSE_EOF'
# AutoMQ Software Cluster with MinIO
# Quick start deployment for local development and testing
version: "3.8"

x-common-variables: &common-env
  KAFKA_S3_ACCESS_KEY: admin
  KAFKA_S3_SECRET_KEY: automq_demo_secret
  KAFKA_HEAP_OPTS: -Xms1g -Xmx4g -XX:MetaspaceSize=96m -XX:MaxDirectMemorySize=1G
  CLUSTER_ID: rqbCPLBqQa2r9n0JMfFCzQ

services:
  minio:
    container_name: "minio"
    image: minio/minio:RELEASE.2025-05-24T17-08-30Z
    environment:
      MINIO_ROOT_USER: admin
      MINIO_ROOT_PASSWORD: automq_demo_secret
      MINIO_DOMAIN: minio
    ports:
      - "9000:9000"
      - "9001:9001"
    command: ["server", "/data", "--console-address", ":9001"]
    networks:
      automq_net:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://minio:9000/minio/health/live"]
      interval: 5s
      timeout: 5s
      retries: 3

  mc:
    container_name: "mc"
    image: minio/mc:RELEASE.2025-05-21T01-59-54Z
    depends_on:
      minio:
        condition: service_healthy
    entrypoint: >
      /bin/sh -c "
      until (/usr/bin/mc alias set minio http://minio:9000 admin automq_demo_secret) do echo '...waiting...' && sleep 1; done;
      /usr/bin/mc rm -r --force minio/automq-data 2>/dev/null || true;
      /usr/bin/mc rm -r --force minio/automq-ops 2>/dev/null || true;
      /usr/bin/mc mb minio/automq-data;
      /usr/bin/mc mb minio/automq-ops;
      /usr/bin/mc anonymous set public minio/automq-data;
      /usr/bin/mc anonymous set public minio/automq-ops;
      echo 'Buckets created successfully';
      tail -f /dev/null
      "
    networks:
      - automq_net

  controller1:
    container_name: "automq-controller1"
    image: automq.azurecr.io/automq/automq-enterprise:5.3.7
    stop_grace_period: 1m
    environment:
      <<: *common-env
    command:
      - bash
      - -c
      - |
        cat > /tmp/server.properties << EOF
        process.roles=broker,controller
        node.id=0
        controller.quorum.voters=0@controller1:9093,1@controller2:9093,2@controller3:9093
        controller.quorum.bootstrap.servers=controller1:9093,controller2:9093,controller3:9093
        listeners=PLAINTEXT://:9092,CONTROLLER://:9093
        inter.broker.listener.name=PLAINTEXT
        advertised.listeners=PLAINTEXT://controller1:9092
        controller.listener.names=CONTROLLER
        log.dirs=/tmp/kraft-combined-logs
        s3.data.buckets=0@s3://automq-data?region=us-east-1&endpoint=http://minio:9000&pathStyle=true
        s3.ops.buckets=1@s3://automq-ops?region=us-east-1&endpoint=http://minio:9000&pathStyle=true
        s3.wal.path=0@s3://automq-data?region=us-east-1&endpoint=http://minio:9000&pathStyle=true
        num.partitions=1
        offsets.topic.replication.factor=1
        transaction.state.log.replication.factor=1
        transaction.state.log.min.isr=1
        EOF
        /opt/automq/kafka/bin/kafka-storage.sh format -t "$$CLUSTER_ID" -c /tmp/server.properties --ignore-formatted || true
        exec /opt/automq/kafka/bin/kafka-server-start.sh /tmp/server.properties
    ports:
      - "19092:9092"
    networks:
      automq_net:
    depends_on:
      minio:
        condition: service_healthy
      mc:
        condition: service_started

  controller2:
    container_name: "automq-controller2"
    image: automq.azurecr.io/automq/automq-enterprise:5.3.7
    stop_grace_period: 1m
    environment:
      <<: *common-env
    command:
      - bash
      - -c
      - |
        cat > /tmp/server.properties << EOF
        process.roles=broker,controller
        node.id=1
        controller.quorum.voters=0@controller1:9093,1@controller2:9093,2@controller3:9093
        controller.quorum.bootstrap.servers=controller1:9093,controller2:9093,controller3:9093
        listeners=PLAINTEXT://:9092,CONTROLLER://:9093
        inter.broker.listener.name=PLAINTEXT
        advertised.listeners=PLAINTEXT://controller2:9092
        controller.listener.names=CONTROLLER
        log.dirs=/tmp/kraft-combined-logs
        s3.data.buckets=0@s3://automq-data?region=us-east-1&endpoint=http://minio:9000&pathStyle=true
        s3.ops.buckets=1@s3://automq-ops?region=us-east-1&endpoint=http://minio:9000&pathStyle=true
        s3.wal.path=0@s3://automq-data?region=us-east-1&endpoint=http://minio:9000&pathStyle=true
        num.partitions=1
        offsets.topic.replication.factor=1
        transaction.state.log.replication.factor=1
        transaction.state.log.min.isr=1
        EOF
        /opt/automq/kafka/bin/kafka-storage.sh format -t "$$CLUSTER_ID" -c /tmp/server.properties --ignore-formatted || true
        exec /opt/automq/kafka/bin/kafka-server-start.sh /tmp/server.properties
    ports:
      - "29092:9092"
    networks:
      automq_net:
    depends_on:
      minio:
        condition: service_healthy
      mc:
        condition: service_started

  controller3:
    container_name: "automq-controller3"
    image: automq.azurecr.io/automq/automq-enterprise:5.3.7
    stop_grace_period: 1m
    environment:
      <<: *common-env
    command:
      - bash
      - -c
      - |
        cat > /tmp/server.properties << EOF
        process.roles=broker,controller
        node.id=2
        controller.quorum.voters=0@controller1:9093,1@controller2:9093,2@controller3:9093
        controller.quorum.bootstrap.servers=controller1:9093,controller2:9093,controller3:9093
        listeners=PLAINTEXT://:9092,CONTROLLER://:9093
        inter.broker.listener.name=PLAINTEXT
        advertised.listeners=PLAINTEXT://controller3:9092
        controller.listener.names=CONTROLLER
        log.dirs=/tmp/kraft-combined-logs
        s3.data.buckets=0@s3://automq-data?region=us-east-1&endpoint=http://minio:9000&pathStyle=true
        s3.ops.buckets=1@s3://automq-ops?region=us-east-1&endpoint=http://minio:9000&pathStyle=true
        s3.wal.path=0@s3://automq-data?region=us-east-1&endpoint=http://minio:9000&pathStyle=true
        num.partitions=1
        offsets.topic.replication.factor=1
        transaction.state.log.replication.factor=1
        transaction.state.log.min.isr=1
        EOF
        /opt/automq/kafka/bin/kafka-storage.sh format -t "$$CLUSTER_ID" -c /tmp/server.properties --ignore-formatted || true
        exec /opt/automq/kafka/bin/kafka-server-start.sh /tmp/server.properties
    ports:
      - "39092:9092"
    networks:
      automq_net:
    depends_on:
      minio:
        condition: service_healthy
      mc:
        condition: service_started

networks:
  automq_net:
    name: automq_net
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: "10.6.0.0/16"
          gateway: "10.6.0.1"
DOCKER_COMPOSE_EOF
print_success "Generated docker-compose.yaml"

# Generate verify.sh
cat > verify.sh << 'VERIFY_EOF'
#!/bin/bash
# AutoMQ Software Verification Script
set -e
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
print_step() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         AutoMQ Software - Cluster Verification               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

print_step "Step 1/4: Checking container status..."
MINIO_STATUS=$(docker ps --filter "name=minio" --filter "status=running" --format "{{.Names}}" | wc -l | tr -d ' ')
CONTROLLER_COUNT=$(docker ps --filter "name=automq-controller" --filter "status=running" --format "{{.Names}}" | wc -l | tr -d ' ')
[ "$MINIO_STATUS" -ge 1 ] && print_success "MinIO is running" || { print_error "MinIO is not running"; exit 1; }
[ "$CONTROLLER_COUNT" -ge 3 ] && print_success "All 3 AutoMQ controllers are running" || { print_error "Only $CONTROLLER_COUNT/3 controllers are running"; exit 1; }
echo ""

print_step "Step 2/4: Checking MinIO buckets..."
docker exec mc /usr/bin/mc ls minio/automq-data > /dev/null 2>&1 && print_success "automq-data bucket exists" || print_error "automq-data bucket not found"
docker exec mc /usr/bin/mc ls minio/automq-ops > /dev/null 2>&1 && print_success "automq-ops bucket exists" || print_error "automq-ops bucket not found"
echo ""

print_step "Step 3/4: Creating test topic..."
docker exec automq-controller1 /opt/automq/kafka/bin/kafka-topics.sh --bootstrap-server controller1:9092 --create --topic test-topic --partitions 3 --replication-factor 1 --if-not-exists 2>/dev/null
print_success "Test topic created (test-topic)"
echo ""

print_step "Step 4/4: Listing cluster topics..."
echo ""
docker exec automq-controller1 /opt/automq/kafka/bin/kafka-topics.sh --bootstrap-server controller1:9092 --list
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  Verification Complete                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  The AutoMQ cluster is healthy and ready to use."
echo ""
VERIFY_EOF
chmod +x verify.sh
print_success "Generated verify.sh"

# Generate cleanup.sh
cat > cleanup.sh << 'CLEANUP_EOF'
#!/bin/bash
# AutoMQ Software Cleanup Script
set -e
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
print_step() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; }

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           AutoMQ Software - Cluster Cleanup                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

read -p "This will remove all AutoMQ containers and data. Continue? [y/N] " -n 1 -r
echo ""
[[ ! $REPLY =~ ^[Yy]$ ]] && { print_warning "Cleanup cancelled"; exit 0; }
echo ""

print_step "Step 1/3: Stopping and removing containers..."
docker compose down -v 2>/dev/null || docker-compose down -v
print_success "Containers stopped and removed"
echo ""

print_step "Step 2/3: Removing network..."
docker network rm automq_net 2>/dev/null || true
print_success "Network removed"
echo ""

print_step "Step 3/3: Cleaning up resources..."
docker volume prune -f --filter "label=com.docker.compose.project=docker-compose" 2>/dev/null || true
print_success "Resources cleaned up"
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Cleanup Complete                           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
CLEANUP_EOF
chmod +x cleanup.sh
print_success "Generated cleanup.sh"

echo ""

# Step 3: Pull Images
print_step "Step 3/5: Pulling container images..."
print_warning "This may take a few minutes on first run..."

docker compose pull 2>/dev/null || docker-compose pull
print_success "Images pulled successfully"

echo ""

# Step 4: Start Services
print_step "Step 4/5: Starting AutoMQ cluster..."

docker compose up -d 2>/dev/null || docker-compose up -d
print_success "Services started"

echo ""

# Step 5: Wait for cluster to be ready
print_step "Step 5/5: Waiting for cluster to be ready..."

MAX_RETRIES=60
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    RUNNING_CONTROLLERS=$(docker ps --filter "name=automq-controller" --filter "status=running" --format "{{.Names}}" | wc -l | tr -d ' ')
    
    if [ "$RUNNING_CONTROLLERS" -ge 3 ]; then
        print_success "All 3 controller nodes are running"
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo -ne "\r  Waiting for controllers... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

echo ""

if [ "$RUNNING_CONTROLLERS" -lt 3 ]; then
    print_warning "Not all controllers started. Check logs with: docker compose logs"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   Installation Complete                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  AutoMQ Bootstrap Servers:"
echo "    - Internal: controller1:9092,controller2:9092,controller3:9092"
echo "    - External: localhost:19092,localhost:29092,localhost:39092"
echo ""
echo "  MinIO Console: http://localhost:9001"
echo "    - Username: admin"
echo "    - Password: automq_demo_secret"
echo ""
echo "  Next Steps:"
echo "    1. Run ./verify.sh to test the cluster"
echo "    2. Run ./cleanup.sh to remove the cluster"
echo ""
