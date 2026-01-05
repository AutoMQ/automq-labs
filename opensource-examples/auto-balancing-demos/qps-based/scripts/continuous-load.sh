#!/bin/bash
# Generate continuous qps to maintain imbalance

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================="
echo "Starting Continuous Load Generation"
echo "========================================="
echo ""

TOPIC="qps-test"
RECORD_SIZE=16  # 16 bytes (lighter load)
THROUGHPUT=2000  # 2000 records/sec (higher QPS)

echo "Configuration:"
echo "  Topic: $TOPIC"
echo "  Record Size: ${RECORD_SIZE} bytes"
echo "  Throughput: ${THROUGHPUT} records/sec"
echo ""

echo "Starting continuous load... (Press Ctrl+C to stop)"
echo ""

# Run continuous load in a loop
while true; do
  docker exec automq-server1-qps bash -c "
    unset KAFKA_JMX_OPTS
    /opt/automq/kafka/bin/kafka-producer-perf-test.sh \
      --topic $TOPIC \
      --num-records 10000 \
      --record-size $RECORD_SIZE \
      --throughput $THROUGHPUT \
      --producer-props \
        bootstrap.servers=server1:9092,server2:9092,server3:9092 \
        linger.ms=100 \
        batch.size=524288 \
        compression.type=lz4
  " 2>&1 | grep "records sent"
  
  sleep 2
done

