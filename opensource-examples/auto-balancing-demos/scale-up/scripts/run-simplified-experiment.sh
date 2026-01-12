#!/bin/bash
# Scale-Up Auto-Balancing - 简化实验

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$DEMO_DIR/results"

LOG_FILE="$RESULTS_DIR/experiment-$(date +%Y%m%d-%H%M%S).log"

echo "=========================================" | tee "$LOG_FILE"
echo "Scale-Up Auto-Balancing Experiment" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "=========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Clean and create results directory
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"

# Start cluster with only 2 brokers first
echo "Starting cluster with 2 brokers..." | tee -a "$LOG_FILE"
docker-compose -f "$DEMO_DIR/docker-compose.yml" up -d minio mc prometheus grafana renderer server1 server2 2>&1 | tee -a "$LOG_FILE"

echo "Waiting 90 seconds for cluster to start..." | tee -a "$LOG_FILE"
sleep 90

# Create topic
echo "Creating topic scaleup-test..." | tee -a "$LOG_FILE"
docker exec -e KAFKA_JMX_OPTS="" automq-server1-scaleup /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 \
    --create --topic scaleup-test --partitions 6 --replication-factor 1 2>&1 | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

sleep 5

# Initial distribution (2 brokers)
echo "Initial Partition Distribution (2 brokers):" | tee -a "$LOG_FILE"
docker exec -e KAFKA_JMX_OPTS="" automq-server1-scaleup /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 --describe --topic scaleup-test 2>&1 | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Start light load
echo "Starting light load generation (1 MB/sec)..." | tee -a "$LOG_FILE"
docker exec -d automq-server1-scaleup bash -c "
  unset KAFKA_JMX_OPTS
  /opt/automq/kafka/bin/kafka-producer-perf-test.sh \
    --topic scaleup-test \
    --num-records 999999999 \
    --record-size 1024 \
    --throughput 1000 \
    --producer-props \
      bootstrap.servers=server1:9092,server2:9092 \
      linger.ms=100 \
      batch.size=524288 \
      compression.type=lz4 \
    > /tmp/load.log 2>&1
"

sleep 10

# Scale up: add server3
echo "=========================================" | tee -a "$LOG_FILE"
echo "SCALING UP: Adding server3 (broker 2)" | tee -a "$LOG_FILE"
echo "=========================================" | tee -a "$LOG_FILE"
docker-compose -f "$DEMO_DIR/docker-compose.yml" up -d server3 2>&1 | tee -a "$LOG_FILE"
echo "✅ Server3 started" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Monitor for 20 minutes
echo "Monitoring partition distribution for 20 minutes..." | tee -a "$LOG_FILE"
for i in {1..40}; do
  echo "=========================================" | tee -a "$LOG_FILE"
  echo "Check $i/40 - $(date +%H:%M:%S)" | tee -a "$LOG_FILE"
  echo "=========================================" | tee -a "$LOG_FILE"
  
  BROKER0=$(docker exec -e KAFKA_JMX_OPTS="" automq-server1-scaleup /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 --describe --topic scaleup-test 2>/dev/null | grep "Partition:" | grep "Leader: 0" | wc -l | tr -d ' ')
  BROKER1=$(docker exec -e KAFKA_JMX_OPTS="" automq-server1-scaleup /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 --describe --topic scaleup-test 2>/dev/null | grep "Partition:" | grep "Leader: 1" | wc -l | tr -d ' ')
  BROKER2=$(docker exec -e KAFKA_JMX_OPTS="" automq-server1-scaleup /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 --describe --topic scaleup-test 2>/dev/null | grep "Partition:" | grep "Leader: 2" | wc -l | tr -d ' ')
  
  echo "Broker 0: $BROKER0 partitions" | tee -a "$LOG_FILE"
  echo "Broker 1: $BROKER1 partitions" | tee -a "$LOG_FILE"
  echo "Broker 2 (NEW): $BROKER2 partitions" | tee -a "$LOG_FILE"
  
  if [ "$BROKER2" -gt 0 ]; then
    echo "✅ REBALANCING DETECTED: Broker 2 received partitions" | tee -a "$LOG_FILE"
  else
    echo "⏳ Waiting for auto-balancer to redistribute..." | tee -a "$LOG_FILE"
  fi
  
  echo "" | tee -a "$LOG_FILE"
  
  if [ $i -lt 40 ]; then
    sleep 30
  fi
done

# Stop load
docker exec automq-server1-scaleup bash -c "pkill -f kafka-producer-perf-test" 2>/dev/null || true

# Final distribution
echo "=========================================" | tee -a "$LOG_FILE"
echo "Final Partition Distribution (3 brokers):" | tee -a "$LOG_FILE"
echo "=========================================" | tee -a "$LOG_FILE"
docker exec -e KAFKA_JMX_OPTS="" automq-server1-scaleup /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 --describe --topic scaleup-test 2>&1 | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "=========================================" | tee -a "$LOG_FILE"
echo "Experiment Completed: $(date)" | tee -a "$LOG_FILE"
echo "=========================================" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"

# Cleanup
docker-compose -f "$DEMO_DIR/docker-compose.yml" down -v 2>&1 | tail -5
