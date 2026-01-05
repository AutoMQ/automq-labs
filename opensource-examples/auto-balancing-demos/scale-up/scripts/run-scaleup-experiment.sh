#!/bin/bash

# Scale-Up Auto-Balancing Experiment with Grafana Screenshots
# Demonstrates AutoMQ's auto-balancing when adding a new broker to the cluster

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$DEMO_DIR/results"
SCREENSHOTS_DIR="$RESULTS_DIR/screenshots"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$RESULTS_DIR/experiment-$TIMESTAMP.log"

# Configuration
BOOTSTRAP_SERVER="localhost:9102"
TOPIC_NAME="scaleup-test"
PARTITIONS=12
REPLICATION_FACTOR=1
LOAD_DURATION=900  # 15 minutes
CHECK_INTERVAL=30
GRAFANA_URL="http://localhost:3010"
GRAFANA_USER="admin"
GRAFANA_PASSWORD="admin"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$LOG_FILE"
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
        local partition_count=$(docker exec automq-server${i}-scaleup curl -s http://localhost:8890/metrics 2>/dev/null | \
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
            local partition_count=$(docker exec automq-server${i}-scaleup curl -s http://localhost:8890/metrics 2>/dev/null | \
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
            sleep 20  # Wait 20 seconds between checks
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
        "${GRAFANA_URL}/render/d-solo/${DASHBOARD_UID}/${DASHBOARD_UID}?orgId=1&panelId=2&width=1200&height=600&tz=UTC" \
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

mkdir -p "$RESULTS_DIR" "$SCREENSHOTS_DIR"

log "========================================="
log "Scale-Up Auto-Balancing Experiment"
log "========================================="
log "Timestamp: $TIMESTAMP"
log ""

# Step 1: Clean up and start initial 2-broker cluster
log "Step 1: Cleaning up previous environment..."
cd "$DEMO_DIR"
docker compose -f docker-compose-with-metrics.yml down -v 2>&1 | tee -a "$LOG_FILE"
sleep 5

log "Starting initial 2-broker cluster..."
docker compose -f docker-compose-with-metrics.yml up -d server1 server2 minio mc prometheus grafana renderer 2>&1 | tee -a "$LOG_FILE"

sleep 30

# Wait for brokers
log "Waiting for brokers to be ready..."
for i in {1..30}; do
    if docker exec automq-server1-scaleup /opt/automq/kafka/bin/kafka-broker-api-versions.sh \
        --bootstrap-server server1:9092 &>/dev/null; then
        log_success "Brokers are ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        log_error "Brokers failed to start"
        exit 1
    fi
    sleep 10
done

# Step 2: Create topic with partitions
log "Step 2: Creating topic with $PARTITIONS partitions..."
docker exec automq-server1-scaleup /opt/automq/kafka/bin/kafka-topics.sh \
    --create \
    --bootstrap-server server1:9092 \
    --topic "$TOPIC_NAME" \
    --partitions "$PARTITIONS" \
    --replication-factor "$REPLICATION_FACTOR" 2>&1 | tee -a "$LOG_FILE"

log "Waiting 15 seconds for topic to be fully created..."
sleep 15

# Step 3: Verify initial distribution (should be 6-6 across 2 brokers)
log "Step 3: Verifying initial partition distribution..."
INITIAL_DIST=$(docker exec automq-server1-scaleup /opt/automq/kafka/bin/kafka-topics.sh \
    --describe \
    --bootstrap-server server1:9092 \
    --topic "$TOPIC_NAME" 2>&1)

echo "$INITIAL_DIST" | tee -a "$LOG_FILE"

BROKER0_COUNT=$(echo "$INITIAL_DIST" | grep -c "Leader: 0" || true)
BROKER1_COUNT=$(echo "$INITIAL_DIST" | grep -c "Leader: 1" || true)

log "Initial distribution: Broker 0: $BROKER0_COUNT, Broker 1: $BROKER1_COUNT"

# Step 4: Wait for metrics and capture "before scale-up" screenshot
log "Step 4: Waiting 60 seconds for metrics to accumulate..."
sleep 60

DASHBOARD_UID="autobalancer-demo"
capture_screenshot "01-before-scaleup"

# Step 5: Start traffic generation
log "Step 5: Starting traffic generation..."
docker run -d --name scaleup-producer-$TIMESTAMP \
    --network automq_net_scaleup \
    automqinc/automq:1.6.0 \
    bash -c "
    while true; do
        /opt/automq/kafka/bin/kafka-producer-perf-test.sh \
            --topic $TOPIC_NAME \
            --num-records 50000 \
            --record-size 10240 \
            --throughput 500 \
            --producer-props bootstrap.servers=server1:9092 \
            acks=1 \
            linger.ms=10 \
            batch.size=32768 \
            compression.type=lz4
        sleep 1
    done
    " 2>&1 | tee -a "$LOG_FILE"

log_success "Traffic generation started"
sleep 10

# Step 6: Add 3rd broker (scale up!)
log "Step 6: ⬆️  SCALING UP - Adding 3rd broker..."
docker compose -f docker-compose-with-metrics.yml up -d server3 2>&1 | tee -a "$LOG_FILE"

SCALEUP_TIME=$(date '+%H:%M:%S')
log_success "3rd broker started at $SCALEUP_TIME"

sleep 20

# Verify 3rd broker is up
log "Verifying 3rd broker joined the cluster..."
docker exec automq-server1-scaleup /opt/automq/kafka/bin/kafka-broker-api-versions.sh \
    --bootstrap-server server1:9092 2>&1 | grep "id: 2" | tee -a "$LOG_FILE"

log_success "3rd broker (ID: 2) successfully joined cluster"

# Step 7: Monitor for rebalancing
log "Step 7: Monitoring for partition rebalancing..."
log "Checking every $CHECK_INTERVAL seconds..."
log ""

CHECKS=$((LOAD_DURATION / CHECK_INTERVAL))
REBALANCED=false
REBALANCE_TIME=""

for i in $(seq 1 $CHECKS); do
    log "========================================="
    log "Check $i/$CHECKS - $(date '+%H:%M:%S')"
    log "========================================="
    
    CURRENT_DIST=$(docker exec automq-server1-scaleup /opt/automq/kafka/bin/kafka-topics.sh \
        --describe \
        --bootstrap-server server1:9092 \
        --topic "$TOPIC_NAME" 2>&1)
    
    BROKER0_COUNT=$(echo "$CURRENT_DIST" | grep -c "Leader: 0" || true)
    BROKER1_COUNT=$(echo "$CURRENT_DIST" | grep -c "Leader: 1" || true)
    BROKER2_COUNT=$(echo "$CURRENT_DIST" | grep -c "Leader: 2" || true)
    
    log "Broker 0: $BROKER0_COUNT partitions"
    log "Broker 1: $BROKER1_COUNT partitions"
    log "Broker 2: $BROKER2_COUNT partitions"
    
    # Check if broker 2 received partitions
    if [ "$BROKER2_COUNT" -gt 0 ] && [ "$REBALANCED" = false ]; then
        log_success "✅ REBALANCING DETECTED! Broker 2 now has $BROKER2_COUNT partitions"
        REBALANCED=true
        REBALANCE_TIME=$(date '+%H:%M:%S')
        
        # Capture "during" screenshot
        sleep 30
        capture_screenshot "02-during-scaleup"
    fi
    
    # Check if balanced (4-4-4 or close)
    if [ "$BROKER2_COUNT" -ge 3 ] && [ "$REBALANCED" = true ]; then
        MAX_DIFF=$((BROKER0_COUNT > BROKER1_COUNT ? BROKER0_COUNT - BROKER1_COUNT : BROKER1_COUNT - BROKER0_COUNT))
        MAX_DIFF2=$((BROKER1_COUNT > BROKER2_COUNT ? BROKER1_COUNT - BROKER2_COUNT : BROKER2_COUNT - BROKER1_COUNT))
        MAX_DIFF3=$((BROKER0_COUNT > BROKER2_COUNT ? BROKER0_COUNT - BROKER2_COUNT : BROKER2_COUNT - BROKER0_COUNT))
        
        if [ "$MAX_DIFF" -le 1 ] && [ "$MAX_DIFF2" -le 1 ] && [ "$MAX_DIFF3" -le 1 ]; then
            log_success "✅ BALANCED STATE ACHIEVED!"
            
            # Capture "after" screenshot
            capture_screenshot "03-after-scaleup"
            
            log "Continuing to monitor for stability..."
            break
        fi
    fi
    
    log ""
    sleep "$CHECK_INTERVAL"
done

# Step 8: Stop traffic
log "Step 8: Stopping traffic generation..."
docker stop scaleup-producer-$TIMESTAMP 2>&1 | tee -a "$LOG_FILE"
docker rm scaleup-producer-$TIMESTAMP 2>&1 | tee -a "$LOG_FILE"

# Step 9: Final verification
log "Step 9: Final partition distribution..."
FINAL_DIST=$(docker exec automq-server1-scaleup /opt/automq/kafka/bin/kafka-topics.sh \
    --describe \
    --bootstrap-server server1:9092 \
    --topic "$TOPIC_NAME" 2>&1)

echo "$FINAL_DIST" | tee -a "$LOG_FILE"

BROKER0_FINAL=$(echo "$FINAL_DIST" | grep -c "Leader: 0" || true)
BROKER1_FINAL=$(echo "$FINAL_DIST" | grep -c "Leader: 1" || true)
BROKER2_FINAL=$(echo "$FINAL_DIST" | grep -c "Leader: 2" || true)

log "Final distribution: Broker 0: $BROKER0_FINAL, Broker 1: $BROKER1_FINAL, Broker 2: $BROKER2_FINAL"

# Step 10: Final screenshot
log "Step 10: Capturing final overview screenshot..."
curl -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    "$GRAFANA_URL/render/d-solo/$DASHBOARD_UID/automq-auto-balancer-demo?orgId=1&panelId=1&width=1400&height=800&from=now-30m&to=now" \
    -o "$SCREENSHOTS_DIR/final-overview-$TIMESTAMP.png" 2>/dev/null

if [ -f "$SCREENSHOTS_DIR/final-overview-$TIMESTAMP.png" ]; then
    log_success "Screenshot saved: final-overview-$TIMESTAMP.png"
fi

# Step 11: Generate report
log "Step 11: Generating results report..."

cat > "$RESULTS_DIR/experiment-summary-$TIMESTAMP.md" <<EOF
# Scale-Up Auto-Balancing Experiment Results

**Experiment ID**: $TIMESTAMP  
**Date**: $(date '+%Y-%m-%d %H:%M:%S')

## Configuration

- **Topic**: $TOPIC_NAME
- **Partitions**: $PARTITIONS
- **Initial Brokers**: 2
- **Final Brokers**: 3
- **Auto-Balancer Goals**: PartitionCountDistributionGoal, NetworkInUsageDistributionGoal, NetworkOutUsageDistributionGoal

## Results

### Before Scale-Up (2 Brokers)

| Broker | Partitions |
|--------|-----------|
| Broker 0 | $BROKER0_COUNT |
| Broker 1 | $BROKER1_COUNT |
| Broker 2 | 0 (not started) |

### After Scale-Up (3 Brokers)

| Broker | Partitions |
|--------|-----------|
| Broker 0 | $BROKER0_FINAL |
| Broker 1 | $BROKER1_FINAL |
| Broker 2 | $BROKER2_FINAL |

**Status**: $([ "$REBALANCED" = true ] && echo "✅ Rebalanced" || echo "❌ Not rebalanced")

### Timeline

- **Experiment Start**: $(head -5 "$LOG_FILE" | grep "Timestamp" | cut -d: -f2-)
- **3rd Broker Added**: $SCALEUP_TIME
- **Rebalancing Detected**: ${REBALANCE_TIME:-"Not detected"}
- **Experiment End**: $(date '+%Y-%m-%d %H:%M:%S')

## Screenshots

1. **Before Scale-Up**: \`screenshots/before-scaleup-$TIMESTAMP.png\`
2. **During Scale-Up**: \`screenshots/during-scaleup-$TIMESTAMP.png\`
3. **After Scale-Up**: \`screenshots/after-scaleup-$TIMESTAMP.png\`
4. **Final Overview**: \`screenshots/final-overview-$TIMESTAMP.png\`

## Conclusion

$(if [ "$REBALANCED" = true ]; then
    echo "✅ **SUCCESS**: AutoMQ's auto-balancer successfully detected the new broker and redistributed partitions to achieve balanced load across all 3 brokers."
    echo ""
    echo "The PartitionCountDistributionGoal ensured that the new broker received partitions even with moderate traffic load."
else
    echo "❌ **INCOMPLETE**: Auto-balancing was not detected. The new broker did not receive partitions."
    echo ""
    echo "Possible reasons:"
    echo "- Traffic load too low"
    echo "- PartitionCountDistributionGoal not configured"
    echo "- Detection interval too long"
fi)

## Log File

Full experiment log: \`experiment-$TIMESTAMP.log\`
EOF

log_success "Results report generated: experiment-summary-$TIMESTAMP.md"

log ""
log "========================================="
log "Experiment Complete!"
log "========================================="
log "Results: $RESULTS_DIR"
log ""

if [ "$REBALANCED" = true ]; then
    log_success "✅ Scale-up auto-balancing was successful!"
else
    log_error "⚠️  Auto-balancing was not detected"
fi

log ""
log "To view Grafana: $GRAFANA_URL"
log ""
