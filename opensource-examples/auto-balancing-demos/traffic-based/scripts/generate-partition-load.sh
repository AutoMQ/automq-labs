#!/bin/bash
# Generate load on specific partition using kafka-console-producer with keys

set -e

PARTITION=$1
TOPIC=${2:-"traffic-test"}
DURATION=${3:-1200}  # 20 minutes default

if [ -z "$PARTITION" ]; then
    echo "Usage: $0 <partition> [topic] [duration_seconds]"
    exit 1
fi

echo "Generating load on partition $PARTITION for $DURATION seconds..."

# Generate records with keys that hash to the target partition
# We'll send ~167 records/sec × 10KB = ~1.67 MB/sec per partition
# 6 partitions × 1.67 MB/sec = ~10 MB/sec total

RECORDS_PER_SEC=167
RECORD_SIZE=10240  # 10KB
INTERVAL=$(echo "scale=6; 1.0 / $RECORDS_PER_SEC" | bc)

END_TIME=$(($(date +%s) + DURATION))

while [ $(date +%s) -lt $END_TIME ]; do
    # Generate a 10KB payload
    PAYLOAD=$(head -c $RECORD_SIZE /dev/urandom | base64 | tr -d '\n')
    
    # Use partition number as key to ensure it goes to the right partition
    echo "partition-${PARTITION}:${PAYLOAD}" | docker exec -i automq-server1-traffic bash -c "
        unset KAFKA_JMX_OPTS
        /opt/automq/kafka/bin/kafka-console-producer.sh \
            --bootstrap-server server1:9092 \
            --topic $TOPIC \
            --property 'parse.key=true' \
            --property 'key.separator=:' \
            --property 'partitioner.class=org.apache.kafka.clients.producer.UniformStickyPartitioner' \
            --producer-property linger.ms=100 \
            --producer-property batch.size=524288 \
            --producer-property compression.type=lz4
    " 2>&1 | grep -v "WARN" || true
    
    sleep $INTERVAL
done

echo "Load generation complete for partition $PARTITION"
