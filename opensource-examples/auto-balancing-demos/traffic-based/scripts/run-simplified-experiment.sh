#!/bin/bash
# Traffic-Based Auto-Balancing - 简化实验
# 专注于验证auto-balancer功能，不依赖JMX/Grafana

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$DEMO_DIR/results"

LOG_FILE="$RESULTS_DIR/experiment-$(date +%Y%m%d-%H%M%S).log"

echo "=========================================" | tee "$LOG_FILE"
echo "Traffic-Based Auto-Balancing Experiment" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "=========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Clean and create results directory
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"

# Create topic
echo "Creating topic traffic-test..." | tee -a "$LOG_FILE"
docker exec -e KAFKA_JMX_OPTS="" automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 \
    --create --topic traffic-test --partitions 6 --replication-factor 1 --if-not-exists 2>&1 | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

sleep 5

# Create imbalance (4-1-1)
echo "Creating imbalance (4-1-1)..." | tee -a "$LOG_FILE"
cat > /tmp/reassignment.json <<EOF
{"version":1,"partitions":[
  {"topic":"traffic-test","partition":0,"replicas":[0]},
  {"topic":"traffic-test","partition":1,"replicas":[0]},
  {"topic":"traffic-test","partition":2,"replicas":[0]},
  {"topic":"traffic-test","partition":3,"replicas":[0]},
  {"topic":"traffic-test","partition":4,"replicas":[1]},
  {"topic":"traffic-test","partition":5,"replicas":[2]}
]}
EOF

docker cp /tmp/reassignment.json automq-server1-traffic:/tmp/
docker exec -e KAFKA_JMX_OPTS="" automq-server1-traffic /opt/automq/kafka/bin/kafka-reassign-partitions.sh \
    --bootstrap-server server1:9092 --reassignment-json-file /tmp/reassignment.json --execute 2>&1 | tee -a "$LOG_FILE"

sleep 15

# Save initial distribution
echo "" | tee -a "$LOG_FILE"
echo "Initial Partition Distribution:" | tee -a "$LOG_FILE"
docker exec -e KAFKA_JMX_OPTS="" automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 --describe --topic traffic-test 2>&1 | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Start load generation (10 MB/sec)
echo "Starting load generation (10 MB/sec)..." | tee -a "$LOG_FILE"
docker exec -d automq-server1-traffic bash -c "
  unset KAFKA_JMX_OPTS
  /opt/automq/kafka/bin/kafka-producer-perf-test.sh \
    --topic traffic-test \
    --num-records 999999999 \
    --record-size 10240 \
    --throughput 1000 \
    --producer-props \
      bootstrap.servers=server1:9092,server2:9092,server3:9092 \
      linger.ms=100 \
      batch.size=524288 \
      compression.type=lz4 \
      partitioner.class=org.apache.kafka.clients.producer.RoundRobinPartitioner \
    > /tmp/load.log 2>&1
"

echo "Load generation started" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Monitor for 20 minutes (40 checks at 30-second intervals)
echo "Monitoring partition distribution for 20 minutes..." | tee -a "$LOG_FILE"
echo "Checking every 30 seconds (40 total checks)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

for i in {1..40}; do
  echo "=========================================" | tee -a "$LOG_FILE"
  echo "Check $i/40 - $(date +%H:%M:%S)" | tee -a "$LOG_FILE"
  echo "=========================================" | tee -a "$LOG_FILE"
  
  # Count partitions per broker
  BROKER0=$(docker exec -e KAFKA_JMX_OPTS="" automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 --describe --topic traffic-test 2>/dev/null | grep "Partition:" | grep "Leader: 0" | wc -l | tr -d ' ')
  BROKER1=$(docker exec -e KAFKA_JMX_OPTS="" automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 --describe --topic traffic-test 2>/dev/null | grep "Partition:" | grep "Leader: 1" | wc -l | tr -d ' ')
  BROKER2=$(docker exec -e KAFKA_JMX_OPTS="" automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 --describe --topic traffic-test 2>/dev/null | grep "Partition:" | grep "Leader: 2" | wc -l | tr -d ' ')
  
  echo "Broker 0: $BROKER0 partitions" | tee -a "$LOG_FILE"
  echo "Broker 1: $BROKER1 partitions" | tee -a "$LOG_FILE"
  echo "Broker 2: $BROKER2 partitions" | tee -a "$LOG_FILE"
  
  # Check if rebalancing occurred
  if [ "$BROKER0" -ne 4 ] || [ "$BROKER1" -ne 1 ] || [ "$BROKER2" -ne 1 ]; then
    echo "✅ REBALANCING DETECTED!" | tee -a "$LOG_FILE"
  else
    echo "⏳ Waiting for auto-balancer to trigger..." | tee -a "$LOG_FILE"
  fi
  
  echo "" | tee -a "$LOG_FILE"
  
  # Wait 30 seconds before next check
  if [ $i -lt 40 ]; then
    sleep 30
  fi
done

# Stop load generation
echo "Stopping load generation..." | tee -a "$LOG_FILE"
docker exec automq-server1-traffic bash -c "pkill -f kafka-producer-perf-test" 2>/dev/null || true
echo "" | tee -a "$LOG_FILE"

# Final distribution
echo "=========================================" | tee -a "$LOG_FILE"
echo "Final Partition Distribution:" | tee -a "$LOG_FILE"
echo "=========================================" | tee -a "$LOG_FILE"
docker exec -e KAFKA_JMX_OPTS="" automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 --describe --topic traffic-test 2>&1 | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "=========================================" | tee -a "$LOG_FILE"
echo "Experiment Completed: $(date)" | tee -a "$LOG_FILE"
echo "=========================================" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
