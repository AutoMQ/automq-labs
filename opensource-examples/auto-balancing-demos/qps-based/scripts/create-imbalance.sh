#!/bin/bash
# Create partition imbalance by reassigning partitions to broker 0

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================="
echo "Creating Partition Imbalance"
echo "========================================="
echo ""

TOPIC="qps-test"

echo "Current partition distribution:"
docker exec automq-server1-qps bash -c "
  unset KAFKA_JMX_OPTS
  /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 \
    --describe \
    --topic $TOPIC
" | grep "Partition:"

echo ""
echo "Creating reassignment plan to move partitions 0,1,3,4 to broker 0..."

# Create reassignment JSON
cat > /tmp/reassignment.json <<EOF
{
  "version": 1,
  "partitions": [
    {"topic": "qps-test", "partition": 0, "replicas": [0]},
    {"topic": "qps-test", "partition": 1, "replicas": [0]},
    {"topic": "qps-test", "partition": 2, "replicas": [0]},
    {"topic": "qps-test", "partition": 3, "replicas": [0]},
    {"topic": "qps-test", "partition": 4, "replicas": [1]},
    {"topic": "qps-test", "partition": 5, "replicas": [2]}
  ]
}
EOF

# Copy reassignment file to container
docker cp /tmp/reassignment.json automq-server1-qps:/tmp/reassignment.json

# Execute reassignment
echo "Executing partition reassignment..."
docker exec automq-server1-qps bash -c "
  unset KAFKA_JMX_OPTS
  /opt/automq/kafka/bin/kafka-reassign-partitions.sh \
    --bootstrap-server server1:9092 \
    --reassignment-json-file /tmp/reassignment.json \
    --execute
"

echo ""
echo "Waiting for reassignment to complete..."
sleep 10

echo ""
echo "New partition distribution:"
docker exec automq-server1-qps bash -c "
  unset KAFKA_JMX_OPTS
  /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 \
    --describe \
    --topic $TOPIC
" | grep "Partition:"

echo ""
echo "========================================="
echo "✓ Imbalance Created"
echo "========================================="
echo ""
echo "Broker 0 now has 4 partitions (0,1,2,3)"
echo "Broker 1 has 1 partition (4)"
echo "Broker 2 has 1 partition (5)"
echo ""
echo "This creates a significant imbalance that auto-balancer should detect."
echo ""

