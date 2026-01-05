#!/bin/bash

# Complete Traffic-Based Auto-Balancing Demo
# Starts cluster, runs experiment, captures screenshots, cleans up

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$DEMO_DIR/results"
SCREENSHOTS_DIR="$RESULTS_DIR/screenshots"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$RESULTS_DIR/complete-demo-$TIMESTAMP.log"

# Configuration
BOOTSTRAP_SERVER="localhost:9092"
TOPIC_NAME="traffic-test"
PARTITIONS=6
REPLICATION_FACTOR=1
GRAFANA_URL="http://localhost:3000"
GRAFANA_USER="admin"
GRAFANA_PASSWORD="admin"
DASHBOARD_UID="autobalancer-demo"
PANEL_ID=2  # Partition distribution panel

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

get_partition_metrics() {
    local label=$1
    log "Querying partition metrics from brokers ($label)..."
    
    local metrics_log="$RESULTS_DIR/metrics-${TIMESTAMP}.log"
    echo "" >> "$metrics_log"
    echo "=== Partition Metrics: $label at $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$metrics_log"
    
    local distribution=""
    for i in 1 2 3; do
        local broker_id=$((i-1))
        
        # Get partition count for user topics (excluding system topics)
        local partition_count=$(docker exec automq-server${i}-traffic curl -s http://localhost:8890/metrics 2>/dev/null | \
            grep "kafka_log_end_offset{" | grep -v "__" | grep "topic=\"$TOPIC_NAME\"" | wc -l | tr -d ' ')
        
        echo "Broker $broker_id: $partition_count partitions" >> "$metrics_log"
        distribution="${distribution}${partition_count} "
        
        # Log to console
        log "  Broker $broker_id: $partition_count partitions"
    done
    
    echo "Distribution: $distribution" >> "$metrics_log"
    log "Distribution: $distribution"
}

wait_for_metrics_stability() {
    local label=$1
    local max_attempts=5
    
    log "Waiting for metrics to stabilize before screenshot..."
    
    local prev_distribution=""
    for attempt in $(seq 1 $max_attempts); do
        local current_distribution=""
        
        for i in 1 2 3; do
            local partition_count=$(docker exec automq-server${i}-traffic curl -s http://localhost:8890/metrics 2>/dev/null | \
                grep "kafka_log_end_offset{" | grep -v "__" | grep "topic=\"$TOPIC_NAME\"" | wc -l | tr -d ' ')
            current_distribution="${current_distribution}${partition_count}-"
        done
        
        log "  Attempt $attempt/$max_attempts: $current_distribution"
        
        if [ "$current_distribution" == "$prev_distribution" ]; then
            log_success "Metrics stable at: $current_distribution"
            return 0
        fi
        
        prev_distribution="$current_distribution"
        
        if [ $attempt -lt $max_attempts ]; then
            sleep 20  # Wait 20 seconds between checks (longer than Prometheus scrape interval)
        fi
    done
    
    log_error "Metrics did not stabilize after $max_attempts attempts"
    return 1
}

capture_screenshot() {
    local name=$1
    local output_file="$SCREENSHOTS_DIR/${name}-${TIMESTAMP}.png"
    
    log "Capturing screenshot: $name"
    
    # Wait for metrics to stabilize
    wait_for_metrics_stability "$name"
    
    # Query and log final metrics
    get_partition_metrics "$name"
    
    # Additional wait for Prometheus to scrape and Grafana to update
    log "Waiting 30 seconds for Prometheus scrape and Grafana update..."
    sleep 30
    
    # Capture screenshot
    curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
        "${GRAFANA_URL}/render/d-solo/${DASHBOARD_UID}/${DASHBOARD_UID}?orgId=1&panelId=${PANEL_ID}&width=1200&height=600&tz=UTC" \
        -o "$output_file"
    
    # Check file size
    local size=$(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null)
    if [ "$size" -gt 10000 ]; then
        log_success "Screenshot captured: $output_file (${size} bytes)"
        
        # Log final verification
        log "Verifying metrics match screenshot..."
        get_partition_metrics "$name-verification"
    else
        log_error "Screenshot too small: $output_file (${size} bytes) - likely 'no data'"
    fi
}

# Create directories
mkdir -p "$RESULTS_DIR" "$SCREENSHOTS_DIR"

log "========================================="
log "Traffic-Based Auto-Balancing Demo"
log "========================================="
log "Timestamp: $TIMESTAMP"
log ""

# Step 1: Start cluster
log "Step 1: Starting Docker cluster..."
cd "$DEMO_DIR"
docker-compose -f docker-compose-clean.yml down -v 2>&1 | tee -a "$LOG_FILE"
sleep 5
docker-compose -f docker-compose-clean.yml up -d 2>&1 | tee -a "$LOG_FILE"

# Step 2: Wait for brokers
log "Step 2: Waiting for brokers to be ready (up to 3 minutes)..."
for i in {1..18}; do
    if docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-broker-api-versions.sh \
        --bootstrap-server server1:9092 &>/dev/null; then
        log_success "Brokers are ready!"
        break
    fi
    if [ $i -eq 18 ]; then
        log_error "Brokers failed to start"
        exit 1
    fi
    sleep 10
done

# Step 3: Wait for Grafana
log "Step 3: Waiting for Grafana to be ready..."
for i in {1..12}; do
    if curl -s "$GRAFANA_URL/api/health" | grep -q "ok"; then
        log_success "Grafana is ready!"
        break
    fi
    if [ $i -eq 12 ]; then
        log_error "Grafana failed to start"
        exit 1
    fi
    sleep 5
done

# Step 4: Create topic
log "Step 4: Creating topic '$TOPIC_NAME' with $PARTITIONS partitions..."
docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --create \
    --bootstrap-server server1:9092 \
    --topic "$TOPIC_NAME" \
    --partitions "$PARTITIONS" \
    --replication-factor "$REPLICATION_FACTOR" \
    --if-not-exists 2>&1 | tee -a "$LOG_FILE"

log "Waiting 15 seconds for topic to be fully created..."
sleep 15

# Verify brokers are still running
log "Verifying brokers are still running..."
for i in 1 2 3; do
    if ! docker ps | grep -q "automq-server${i}-traffic"; then
        log_error "Broker server${i} is not running!"
        docker logs automq-server${i}-traffic 2>&1 | tail -50 | tee -a "$LOG_FILE"
        exit 1
    fi
done
log_success "All brokers are running"

# Step 5: Create imbalanced distribution (4-1-1)
log "Step 5: Creating imbalanced partition distribution (4-1-1)..."
cat > /tmp/reassignment.json <<EOF
{
  "version": 1,
  "partitions": [
    {"topic": "$TOPIC_NAME", "partition": 0, "replicas": [0]},
    {"topic": "$TOPIC_NAME", "partition": 1, "replicas": [0]},
    {"topic": "$TOPIC_NAME", "partition": 2, "replicas": [0]},
    {"topic": "$TOPIC_NAME", "partition": 3, "replicas": [0]},
    {"topic": "$TOPIC_NAME", "partition": 4, "replicas": [1]},
    {"topic": "$TOPIC_NAME", "partition": 5, "replicas": [2]}
  ]
}
EOF

docker cp /tmp/reassignment.json automq-server1-traffic:/tmp/
docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-reassign-partitions.sh \
    --bootstrap-server server1:9092 \
    --reassignment-json-file /tmp/reassignment.json \
    --execute 2>&1 | tee -a "$LOG_FILE"

log "Waiting 30 seconds for reassignment to complete..."
sleep 30

# Step 6: Verify initial distribution
log "Step 6: Verifying initial partition distribution..."
docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 \
    --describe \
    --topic "$TOPIC_NAME" 2>&1 | tee -a "$LOG_FILE"

# Step 7: Wait for metrics to accumulate
log "Step 7: Waiting 90 seconds for metrics to accumulate..."
sleep 90

# Step 8: Capture "before" screenshot
capture_screenshot "01-before-load"

# Step 9: Start load generation
log "Step 9: Starting load generation (10 MB/sec)..."
docker exec -d automq-server1-traffic bash -c "
  /opt/automq/kafka/bin/kafka-producer-perf-test.sh \
    --topic $TOPIC_NAME \
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

log_success "Load generation started"

# Step 10: Wait for auto-balancer to detect and rebalance
log "Step 10: Monitoring for auto-balancing (checking every 30s for 10 minutes)..."
balanced=false
for i in {1..20}; do
    sleep 30
    log "Check $i/20: Checking partition distribution..."
    
    # Get current distribution
    distribution=$(docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
        --bootstrap-server server1:9092 \
        --describe \
        --topic "$TOPIC_NAME" 2>/dev/null | grep "Leader:" | awk '{print $6}' | sort | uniq -c)
    
    log "Current distribution: $distribution"
    
    # Check if balanced (each broker should have 2 partitions)
    broker0_count=$(echo "$distribution" | grep " 0$" | awk '{print $1}' || echo "0")
    broker1_count=$(echo "$distribution" | grep " 1$" | awk '{print $1}' || echo "0")
    broker2_count=$(echo "$distribution" | grep " 2$" | awk '{print $1}' || echo "0")
    
    if [ "$broker0_count" == "2" ] && [ "$broker1_count" == "2" ] && [ "$broker2_count" == "2" ]; then
        log_success "Partitions are balanced! (2-2-2)"
        balanced=true
        
        # Capture "during" screenshot
        sleep 30
        capture_screenshot "02-during-rebalance"
        break
    fi
    
    # Capture "during" screenshot at 5 minutes
    if [ $i -eq 10 ]; then
        capture_screenshot "02-during-rebalance"
    fi
done

if [ "$balanced" = false ]; then
    log_error "Auto-balancing did not complete within 10 minutes"
fi

# Step 11: Continue monitoring for 2 more minutes
log "Step 11: Continuing monitoring for 2 more minutes..."
sleep 120

# Step 12: Capture "after" screenshot
capture_screenshot "03-after-rebalance"

# Step 13: Final distribution
log "Step 13: Final partition distribution:"
docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 \
    --describe \
    --topic "$TOPIC_NAME" 2>&1 | tee -a "$LOG_FILE"

# Step 14: Stop load
log "Step 14: Stopping load generation..."
docker exec automq-server1-traffic pkill -f kafka-producer-perf-test || true

# Step 15: Summary
log ""
log "========================================="
log "Demo Complete!"
log "========================================="
log "Results directory: $RESULTS_DIR"
log "Screenshots directory: $SCREENSHOTS_DIR"
log "Log file: $LOG_FILE"
log ""

# List screenshots
log "Screenshots captured:"
ls -lh "$SCREENSHOTS_DIR"/*-${TIMESTAMP}.png 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' | tee -a "$LOG_FILE"

log ""
if [ "$balanced" = true ]; then
    log_success "✅ Demo completed successfully - auto-balancing worked!"
else
    log_error "❌ Demo completed but auto-balancing did not finish"
fi

log ""
log "To clean up: docker-compose -f docker-compose-clean.yml down -v"
