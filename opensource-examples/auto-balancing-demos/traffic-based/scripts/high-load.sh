#!/bin/bash
# Generate HIGH load to trigger auto-balancer (10 MB/sec)

set -e

echo "==========================================="
echo "Starting HIGH Load Generation (10 MB/sec)"
echo "==========================================="
echo ""

TOPIC="traffic-test"
RECORD_SIZE=10240  # 10KB
THROUGHPUT=1000    # 1000 records/sec × 10KB = 10 MB/sec

echo "Configuration:"
echo "  Topic: $TOPIC"
echo "  Record Size: ${RECORD_SIZE} bytes (10KB)"
echo "  Throughput: ${THROUGHPUT} records/sec"
echo "  Total: 10 MB/sec"
echo ""

echo "Starting continuous high load..."
echo ""

while true; do
    docker exec automq-server1-traffic bash -c "
        unset KAFKA_JMX_OPTS
        /opt/automq/kafka/bin/kafka-producer-perf-test.sh \
            --topic $TOPIC \
            --num-records 30000 \
            --record-size $RECORD_SIZE \
            --throughput $THROUGHPUT \
            --producer-props \
                bootstrap.servers=server1:9092,server2:9092,server3:9092 \
                linger.ms=100 \
                batch.size=524288 \
                buffer.memory=134217728 \
                compression.type=lz4 \
                partitioner.class=org.apache.kafka.clients.producer.RoundRobinPartitioner
    " 2>&1 | grep -v "WARN"
    
    sleep 1
done
