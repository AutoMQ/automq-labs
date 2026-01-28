#!/bin/bash
# AutoMQ Software Verification Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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

print_error() {
    echo -e "${RED}✗${NC} $1"
}

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         AutoMQ Software - Cluster Verification             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Check container status
print_step "Step 1/4: Checking container status..."

MINIO_STATUS=$(docker ps --filter "name=minio" --filter "status=running" --format "{{.Names}}" | wc -l | tr -d ' ')
CONTROLLER_COUNT=$(docker ps --filter "name=automq-controller" --filter "status=running" --format "{{.Names}}" | wc -l | tr -d ' ')

if [ "$MINIO_STATUS" -ge 1 ]; then
    print_success "MinIO is running"
else
    print_error "MinIO is not running"
    exit 1
fi

if [ "$CONTROLLER_COUNT" -ge 3 ]; then
    print_success "All 3 AutoMQ controllers are running"
else
    print_error "Only $CONTROLLER_COUNT/3 controllers are running"
    exit 1
fi

echo ""

# Step 2: Check MinIO buckets
print_step "Step 2/4: Checking MinIO buckets..."

docker exec mc /usr/bin/mc ls minio/automq-data > /dev/null 2>&1 && print_success "automq-data bucket exists" || print_error "automq-data bucket not found"
docker exec mc /usr/bin/mc ls minio/automq-ops > /dev/null 2>&1 && print_success "automq-ops bucket exists" || print_error "automq-ops bucket not found"

echo ""

# Step 3: Create test topic
print_step "Step 3/4: Creating test topic..."

docker exec automq-controller1 /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server controller1:9092 \
    --create \
    --topic test-topic \
    --partitions 3 \
    --replication-factor 1 \
    --if-not-exists 2>/dev/null

print_success "Test topic created (test-topic)"

echo ""

# Step 4: List topics
print_step "Step 4/4: Listing cluster topics..."

echo ""
docker exec automq-controller1 /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server controller1:9092 \
    --list

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  Verification Complete                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  The AutoMQ cluster is healthy and ready to use."
echo ""
echo "  Quick Commands:"
echo ""
echo "  # Create a topic"
echo "  docker exec automq-controller1 /opt/automq/kafka/bin/kafka-topics.sh \\"
echo "    --bootstrap-server controller1:9092 \\"
echo "    --create --topic my-topic --partitions 3 --replication-factor 1"
echo ""
echo "  # Produce messages"
echo "  docker exec -it automq-controller1 /opt/automq/kafka/bin/kafka-console-producer.sh \\"
echo "    --bootstrap-server controller1:9092 --topic my-topic"
echo ""
echo "  # Consume messages"
echo "  docker exec -it automq-controller1 /opt/automq/kafka/bin/kafka-console-consumer.sh \\"
echo "    --bootstrap-server controller1:9092 --topic my-topic --from-beginning"
echo ""
