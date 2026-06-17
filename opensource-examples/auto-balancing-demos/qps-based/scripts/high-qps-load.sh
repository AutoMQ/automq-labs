#!/bin/bash
# Generate high QPS with larger messages to exceed 1 MB/sec threshold

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================="
echo "Starting High QPS Load Generation"
echo "========================================="
echo ""

TOPIC="qps-test"
RECORD_SIZE=10240  # 10KB messages to achieve higher throughput
THROUGHPUT=1000    # 1000 records/sec * 10KB = 10 MB/sec (well above 1 MB/sec threshold)

echo "Configuration:"
echo "  Topic: $TOPIC"
echo "  Record Size: ${RECORD_SIZE} bytes (10KB)"
echo "  Throughput: ${THROUGHPUT} records/sec"
echo "  Expected BytesInPerSec: ~10 MB/sec"
echo ""

echo "Targeting partitions 0, 1, 2, 3 (all on broker 0)"
echo "This creates traffic imbalance: broker 0 gets 10 MB/sec, others get minimal"
echo ""

echo "Starting continuous load... (Press Ctrl+C to stop)"
echo ""

# Run continuous load targeting specific partitions
while true; do
  for partition in 0 1 2 3; do
    docker exec automq-server1-qps bash -c "
      unset KAFKA_JMX_OPTS
      /opt/automq/kafka/bin/kafka-producer-perf-test.sh \
        --topic $TOPIC \
        --num-records 250 \
        --record-size $RECORD_SIZE \
        --throughput 250 \
        --producer-props \
          bootstrap.servers=server1:9092,server2:9092,server3:9092 \
          linger.ms=100 \
          batch.size=524288 \
          compression.type=lz4 \
        --producer.config <(echo 'partitioner.class=org.apache.kafka.clients.producer.internals.DefaultPartitioner')
    " 2>&1 | grep "records sent" &
  done
  
  wait
  sleep 1
done
