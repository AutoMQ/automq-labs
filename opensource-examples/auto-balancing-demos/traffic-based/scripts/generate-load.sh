#!/bin/bash
# Generate traffic imbalance by sending high-volume traffic to specific partitions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================="
echo "Generating Traffic Imbalance"
echo "========================================="
echo ""

# Configuration
TOPIC="traffic-test"
RECORD_SIZE=10240  # 10KB records
NUM_RECORDS=100000
THROUGHPUT=-1  # Unlimited

echo "Configuration:"
echo "  Topic: $TOPIC"
echo "  Record Size: ${RECORD_SIZE} bytes"
echo "  Number of Records: $NUM_RECORDS"
echo "  Target: Partitions 0,1,2 (should be on broker 0)"
echo ""

# Generate load targeting specific partitions
echo "Starting load generation..."
echo "This will create traffic imbalance by sending most traffic to broker 0"
echo ""

docker exec automq-server1-traffic bash -c "
  unset KAFKA_JMX_OPTS
  /opt/automq/kafka/bin/kafka-producer-perf-test.sh \
    --topic $TOPIC \
    --num-records $NUM_RECORDS \
    --record-size $RECORD_SIZE \
    --throughput $THROUGHPUT \
    --producer-props \
      bootstrap.servers=server1:9092,server2:9092,server3:9092 \
      linger.ms=100 \
      batch.size=524288 \
      buffer.memory=134217728 \
      max.request.size=67108864 \
      compression.type=lz4
"

echo ""
echo "========================================="
echo "✓ Load Generation Complete"
echo "========================================="
echo ""
echo "Traffic imbalance has been created."
echo "Most traffic should now be going to broker 0 (server1)."
echo ""
echo "Next steps:"
echo "  1. Run ./scripts/collect-metrics.sh before"
echo "  2. Wait for auto-balancer to detect and fix imbalance"
echo "  3. Run ./scripts/verify-balance.sh to monitor progress"
echo ""
