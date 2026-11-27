#!/bin/bash
# Generate continuous load for scale-up demo

set -e

echo "==========================================="
echo "Starting Continuous Load Generation"
echo "==========================================="
echo ""

# Configuration
TOPIC="scaleup-test"
RECORD_SIZE=1024  # 1KB records
THROUGHPUT=1000   # 1000 records/sec = 1 MB/sec

echo "Configuration:"
echo "  Topic: $TOPIC"
echo "  Record Size: ${RECORD_SIZE} bytes"
echo "  Throughput: ${THROUGHPUT} records/sec"
echo ""

echo "Starting continuous load... (Press Ctrl+C to stop)"
echo ""

# Run continuous load
while true; do
    docker exec automq-server1-scaleup bash -c "
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
                compression.type=lz4
    " 2>&1 | grep -v "WARN"
    
    sleep 1
done
