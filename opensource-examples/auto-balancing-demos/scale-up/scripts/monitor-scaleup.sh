#!/bin/bash

DURATION=600  # 10 minutes
INTERVAL=30   # 30 seconds
CHECKS=$((DURATION / INTERVAL))

echo "==========================================="
echo "Monitoring Auto-Balancer for $DURATION seconds"
echo "Checks: $CHECKS (every $INTERVAL seconds)"
echo "==========================================="

for i in $(seq 1 $CHECKS); do
    echo ""
    echo "Check $i/$CHECKS at $(date '+%Y-%m-%d %H:%M:%S')"
    echo "-------------------------------------------"
    
    docker exec automq-server1-scaleup bash -c "unset KAFKA_JMX_OPTS && /opt/automq/kafka/bin/kafka-topics.sh --describe --topic scaleup-test --bootstrap-server server1:9092" | grep "Partition:"
    
    echo ""
    sleep $INTERVAL
done

echo ""
echo "==========================================="
echo "Monitoring Complete"
echo "==========================================="
