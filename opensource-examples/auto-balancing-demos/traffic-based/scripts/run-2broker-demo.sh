#!/bin/bash

# 2-Broker Traffic-Based Auto-Balancing Demo
# Uses 2 brokers with 4 partitions (3-1 -> 2-2)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$DEMO_DIR/results"
SCREENSHOTS_DIR="$RESULTS_DIR/screenshots"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$RESULTS_DIR/2broker-demo-$TIMESTAMP.log"

# Configuration
TOPIC_NAME="traffic-test"
PARTITIONS=4
REPLICATION_FACTOR=1
GRAFANA_URL="http://localhost:3000"
GRAFANA_USER="admin"
GRAFANA_PASSWORD="admin"
DASHBOARD_UID="autobalancer-demo"
PANEL_ID=1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ❌ $1${NC}" | tee -a "$LOG_FILE"
}

capture_screenshot() {
    local name=$1
    local output_file="$SCREENSHOTS_DIR/${name}-${TIMESTAMP}.png"
    
    log "Capturing screenshot: $name"
    sleep 10
    
    curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
        "${GRAFANA_URL}/render/d-solo/${DASHBOARD_UID}/${DASHBOARD_UID}?orgId=1&panelId=${PANEL_ID}&width=1200&height=600&tz=UTC" \
        -o "$output_file"
    
    local size=$(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null)
    if [ "$size" -gt 10000 ]; then
        log_success "Screenshot: $output_file (${size} bytes)"
    else
        log_error "Screenshot too small: $output_file (${size} bytes)"
    fi
}

mkdir -p "$RESULTS_DIR" "$SCREENSHOTS_DIR"

log "========================================="
log "2-Broker Traffic-Based Auto-Balancing"
log "========================================="
log "Timestamp: $TIMESTAMP"
log ""

# Step 1: Start cluster
log "Step 1: Starting 2-broker cluster..."
cd "$DEMO_DIR"
docker-compose -f docker-compose-2broker.yml down -v 2>&1 | tee -a "$LOG_FILE"
sleep 5
docker-compose -f docker-compose-2broker.yml up -d 2>&1 | tee -a "$LOG_FILE"

# Step 2: Wait for brokers
log "Step 2: Waiting for brokers (up to 3 minutes)..."
for i in {1..18}; do
    if docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-broker-api-versions.sh \
        --bootstrap-server server1:9092 &>/dev/null; then
        log_success "Brokers ready!"
        break
    fi
    if [ $i -eq 18 ]; then
        log_error "Brokers failed to start"
        exit 1
    fi
    sleep 10
done

# Step 3: Wait for Grafana
log "Step 3: Waiting for Grafana..."
for i in {1..12}; do
    if curl -s "$GRAFANA_URL/api/health" | grep -q "ok"; then
        log_success "Grafana ready!"
        break
    fi
    if [ $i -eq 12 ]; then
        log_error "Grafana failed"
        exit 1
    fi
    sleep 5
done

# Step 4: Create topic
log "Step 4: Creating topic with $PARTITIONS partitions..."
docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --create \
    --bootstrap-server server1:9092 \
    --topic "$TOPIC_NAME" \
    --partitions "$PARTITIONS" \
    --replication-factor "$REPLICATION_FACTOR" \
    --if-not-exists 2>&1 | tee -a "$LOG_FILE"

sleep 5

# Step 5: Create imbalanced distribution (3-1)
log "Step 5: Creating imbalanced distribution (3-1)..."
cat > /tmp/reassignment.json <<EOF
{
  "version": 1,
  "partitions": [
    {"topic": "$TOPIC_NAME", "partition": 0, "replicas": [0]},
    {"topic": "$TOPIC_NAME", "partition": 1, "replicas": [0]},
    {"topic": "$TOPIC_NAME", "partition": 2, "replicas": [0]},
    {"topic": "$TOPIC_NAME", "partition": 3, "replicas": [1]}
  ]
}
EOF

docker cp /tmp/reassignment.json automq-server1-traffic:/tmp/
docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-reassign-partitions.sh \
    --bootstrap-server server1:9092 \
    --reassignment-json-file /tmp/reassignment.json \
    --execute 2>&1 | tee -a "$LOG_FILE"

sleep 20

# Step 6: Verify initial distribution
log "Step 6: Initial distribution:"
docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 \
    --describe \
    --topic "$TOPIC_NAME" 2>&1 | tee -a "$LOG_FILE"

# Step 7: Wait for metrics
log "Step 7: Waiting 90s for metrics..."
sleep 90

# Step 8: Capture "before" screenshot
capture_screenshot "01-before-load"

# Step 9: Start load
log "Step 9: Starting load (10 MB/sec)..."
docker exec -d automq-server1-traffic bash -c "
  /opt/automq/kafka/bin/kafka-producer-perf-test.sh \
    --topic $TOPIC_NAME \
    --num-records 999999999 \
    --record-size 10240 \
    --throughput 1000 \
    --producer-props \
      bootstrap.servers=server1:9092,server2:9092 \
      linger.ms=100 \
      batch.size=524288 \
      compression.type=lz4 \
      partitioner.class=org.apache.kafka.clients.producer.RoundRobinPartitioner \
    > /tmp/load.log 2>&1
"

log_success "Load started"

# Step 10: Monitor for rebalancing
log "Step 10: Monitoring (every 30s for 10 minutes)..."
balanced=false
for i in {1..20}; do
    sleep 30
    log "Check $i/20..."
    
    distribution=$(docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
        --bootstrap-server server1:9092 \
        --describe \
        --topic "$TOPIC_NAME" 2>/dev/null | grep "Leader:" | awk '{print $6}' | sort | uniq -c)
    
    log "Distribution: $distribution"
    
    broker0=$(echo "$distribution" | grep " 0$" | awk '{print $1}' || echo "0")
    broker1=$(echo "$distribution" | grep " 1$" | awk '{print $1}' || echo "0")
    
    if [ "$broker0" == "2" ] && [ "$broker1" == "2" ]; then
        log_success "Balanced! (2-2)"
        balanced=true
        sleep 30
        capture_screenshot "02-during-rebalance"
        break
    fi
    
    if [ $i -eq 10 ]; then
        capture_screenshot "02-during-rebalance"
    fi
done

if [ "$balanced" = false ]; then
    log_error "Auto-balancing did not complete"
fi

# Step 11: Continue monitoring
log "Step 11: Continuing for 2 minutes..."
sleep 120

# Step 12: Capture "after" screenshot
capture_screenshot "03-after-rebalance"

# Step 13: Final distribution
log "Step 13: Final distribution:"
docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 \
    --describe \
    --topic "$TOPIC_NAME" 2>&1 | tee -a "$LOG_FILE"

# Step 14: Stop load
log "Step 14: Stopping load..."
docker exec automq-server1-traffic pkill -f kafka-producer-perf-test || true

# Summary
log ""
log "========================================="
log "Demo Complete!"
log "========================================="
log "Results: $RESULTS_DIR"
log "Screenshots: $SCREENSHOTS_DIR"
log "Log: $LOG_FILE"
log ""

ls -lh "$SCREENSHOTS_DIR"/*-${TIMESTAMP}.png 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' | tee -a "$LOG_FILE"

log ""
if [ "$balanced" = true ]; then
    log_success "✅ Auto-balancing successful!"
else
    log_error "❌ Auto-balancing did not finish"
fi

log ""
log "Cleanup: docker-compose -f docker-compose-2broker.yml down -v"
