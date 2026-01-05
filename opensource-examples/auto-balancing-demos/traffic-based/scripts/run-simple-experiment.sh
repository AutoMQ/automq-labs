#!/bin/bash
# Simplified traffic-based experiment - assumes cluster is already running

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$DEMO_DIR/results"

echo "=============================================="
echo "Traffic-Based Auto-Balancing Experiment"
echo "=============================================="

# Clean results
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR/screenshots" "$RESULTS_DIR/before" "$RESULTS_DIR/after"

# Create topic
echo "Creating topic..."
docker exec -e KAFKA_JMX_OPTS="" automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 \
    --create --topic traffic-test --partitions 6 --replication-factor 1 --if-not-exists

# Create imbalance
echo "Creating imbalance (4-1-1)..."
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
    --bootstrap-server server1:9092 --reassignment-json-file /tmp/reassignment.json --execute

sleep 15

# Save initial state
docker exec -e KAFKA_JMX_OPTS="" automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 --describe --topic traffic-test | grep "Partition:" > "$RESULTS_DIR/before/distribution.txt"

# Generate BEFORE screenshots
echo "Generating BEFORE screenshots..."
bash "$SCRIPT_DIR/generate-screenshots.sh" before

# Start load (10 MB/sec with RoundRobinPartitioner)
echo "Starting load generation (10 MB/sec, 20 minutes)..."
bash "$SCRIPT_DIR/high-load.sh" > "$RESULTS_DIR/load.log" 2>&1 &
LOAD_PID=$!

sleep 30

# Monitor for 20 minutes
echo "Monitoring for 20 minutes..."
bash "$SCRIPT_DIR/monitor-20min.sh"

# Stop load
kill $LOAD_PID 2>/dev/null || true
sleep 5

# Generate AFTER screenshots
echo "Generating AFTER screenshots..."
bash "$SCRIPT_DIR/generate-screenshots.sh" after

# Save final state
docker exec -e KAFKA_JMX_OPTS="" automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 --describe --topic traffic-test | grep "Partition:" > "$RESULTS_DIR/after/distribution.txt"

# Count partitions
BROKER0=$(grep -c "Leader: 0" "$RESULTS_DIR/after/distribution.txt" || echo "0")
BROKER1=$(grep -c "Leader: 1" "$RESULTS_DIR/after/distribution.txt" || echo "0")
BROKER2=$(grep -c "Leader: 2" "$RESULTS_DIR/after/distribution.txt" || echo "0")

echo ""
echo "=============================================="
echo "Experiment Complete"
echo "=============================================="
echo "Final distribution: $BROKER0-$BROKER1-$BROKER2"
echo "Expected: 2-2-2"
echo "Screenshots: $(ls -1 "$RESULTS_DIR/screenshots/"*.png 2>/dev/null | wc -l | tr -d ' ') files"
echo "Results saved to: $RESULTS_DIR"
