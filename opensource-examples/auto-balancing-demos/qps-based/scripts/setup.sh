#!/bin/bash
# Setup script for qps-based auto-balancing demo
# This script starts all containers and prepares the environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
COMMON_DIR="$(dirname "$DEMO_DIR")/common"

echo "========================================="
echo "QPS-Based Auto-Balancing Demo Setup"
echo "========================================="
echo ""

# Check if docker is running
if ! docker info > /dev/null 2>&1; then
    echo "✗ Docker is not running. Please start Docker and try again."
    exit 1
fi

echo "✓ Docker is running"
echo ""

# Start docker compose services
echo "Starting Docker Compose services..."
cd "$DEMO_DIR"
docker compose up -d

echo ""
echo "Waiting for containers to be healthy..."

# Wait for MinIO
"$COMMON_DIR/scripts/wait-for-container.sh" minio-qps 120

# Wait for brokers
"$COMMON_DIR/scripts/wait-for-container.sh" automq-server1-qps 180
"$COMMON_DIR/scripts/wait-for-container.sh" automq-server2-qps 180
"$COMMON_DIR/scripts/wait-for-container.sh" automq-server3-qps 180

# Wait for Prometheus
"$COMMON_DIR/scripts/wait-for-container.sh" prometheus-qps 60

# Wait for Grafana
"$COMMON_DIR/scripts/wait-for-container.sh" grafana-qps 60

echo ""
echo "Waiting additional 30 seconds for services to stabilize..."
sleep 30

echo ""
echo "Creating test topic..."
docker exec automq-server1-qps bash -c "
  unset KAFKA_JMX_OPTS
  /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 \
    --create \
    --topic qps-test \
    --partitions 6 \
    --replication-factor 1 \
    --if-not-exists
"

echo ""
echo "Verifying topic creation..."
docker exec automq-server1-qps bash -c "
  unset KAFKA_JMX_OPTS
  /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 \
    --describe \
    --topic qps-test
"

echo ""
echo "========================================="
echo "✓ Setup Complete!"
echo "========================================="
echo ""
echo "Services:"
echo "  - AutoMQ Brokers: localhost:9092, localhost:9093, localhost:9094"
echo "  - MinIO Console: http://localhost:9001 (minioadmin/minioadmin)"
echo "  - Prometheus: http://localhost:9090"
echo "  - Grafana: http://localhost:3000 (admin/admin)"
echo ""
echo "Next steps:"
echo "  1. Run ./scripts/generate-load.sh to create qps imbalance"
echo "  2. Run ./scripts/collect-metrics.sh before to collect initial metrics"
echo "  3. Wait for auto-balancer (or run ./scripts/verify-balance.sh)"
echo "  4. Run ./scripts/collect-metrics.sh after to collect final metrics"
echo ""
