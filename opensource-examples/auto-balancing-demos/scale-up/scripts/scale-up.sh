#!/bin/bash
# Scale up from 2 brokers to 3 brokers

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"

echo "==========================================="
echo "Scaling Up: Adding Server3"
echo "==========================================="
echo ""

echo "Current cluster state (2 brokers):"
docker exec automq-server1-scaleup bash -c "unset KAFKA_JMX_OPTS && /opt/automq/kafka/bin/kafka-topics.sh --describe --topic scaleup-test --bootstrap-server server1:9092" | grep "Partition:"
echo ""

echo "Starting server3..."
echo ""

# Start server3 using docker compose
cd "$DEMO_DIR"

# Uncomment server3 in docker-compose.yml temporarily
cp docker-compose.yml docker-compose.yml.backup

# Use sed to uncomment server3 section
sed -i.tmp '/# server3:/,/# networks:/s/^  # /  /' docker-compose.yml
rm -f docker-compose.yml.tmp

# Start server3
docker compose up -d server3

echo ""
echo "Waiting for server3 to start (90 seconds)..."
sleep 90

echo ""
echo "New cluster state (3 brokers):"
docker exec automq-server1-scaleup bash -c "unset KAFKA_JMX_OPTS && /opt/automq/kafka/bin/kafka-topics.sh --describe --topic scaleup-test --bootstrap-server server1:9092" | grep "Partition:"

echo ""
echo "==========================================="
echo "✓ Scale-Up Complete"
echo "==========================================="
echo ""
echo "Server3 has been added to the cluster."
echo "Auto-balancer should detect the new broker and rebalance partitions."
echo ""
echo "Expected final distribution: 2-2-2 (2 partitions per broker)"
echo ""
