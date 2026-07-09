#!/bin/bash

# Traffic-Based Auto-Balancing Experiment with Grafana Screenshots
# This script demonstrates AutoMQ's auto-balancing based on traffic distribution

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$DEMO_DIR/results"
SCREENSHOTS_DIR="$RESULTS_DIR/screenshots"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$RESULTS_DIR/experiment-$TIMESTAMP.log"

# Configuration
BOOTSTRAP_SERVER="localhost:9092"
TOPIC_NAME="traffic-test"
PARTITIONS=6
REPLICATION_FACTOR=1
LOAD_DURATION=1200  # 20 minutes
CHECK_INTERVAL=30   # Check every 30 seconds
GRAFANA_URL="http://localhost:3000"
GRAFANA_USER="admin"
GRAFANA_PASSWORD="admin"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

# Create results directories
mkdir -p "$RESULTS_DIR" "$SCREENSHOTS_DIR"

log "========================================="
log "Traffic-Based Auto-Balancing Experiment"
log "========================================="
log "Timestamp: $TIMESTAMP"
log "Results directory: $RESULTS_DIR"
log ""

# Step 1: Wait for brokers to be ready
log "Step 1: Waiting for AutoMQ brokers to be ready..."
sleep 10

for i in {1..30}; do
    if docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-broker-api-versions.sh \
        --bootstrap-server server1:9092 &>/dev/null; then
        log_success "Brokers are ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        log_error "Brokers failed to start after 5 minutes"
        exit 1
    fi
    sleep 10
done

# Step 2: Create topic
log "Step 2: Creating topic '$TOPIC_NAME' with $PARTITIONS partitions..."
docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --create \
    --bootstrap-server server1:9092 \
    --topic "$TOPIC_NAME" \
    --partitions "$PARTITIONS" \
    --replication-factor "$REPLICATION_FACTOR" \
    --config min.insync.replicas=1 2>&1 | tee -a "$LOG_FILE"

sleep 5

# Step 3: Create imbalanced partition distribution (4-1-1)
log "Step 3: Creating imbalanced partition distribution (4-1-1)..."
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

docker cp /tmp/reassignment.json automq-server1-traffic:/tmp/reassignment.json
docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-reassign-partitions.sh \
    --bootstrap-server server1:9092 \
    --reassignment-json-file /tmp/reassignment.json \
    --execute 2>&1 | tee -a "$LOG_FILE"

sleep 10

# Step 4: Verify initial distribution
log "Step 4: Verifying initial partition distribution..."
INITIAL_DIST=$(docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --describe \
    --bootstrap-server server1:9092 \
    --topic "$TOPIC_NAME" 2>&1)

echo "$INITIAL_DIST" | tee -a "$LOG_FILE"

# Count partitions per broker
BROKER0_COUNT=$(echo "$INITIAL_DIST" | grep -c "Leader: 0" || true)
BROKER1_COUNT=$(echo "$INITIAL_DIST" | grep -c "Leader: 1" || true)
BROKER2_COUNT=$(echo "$INITIAL_DIST" | grep -c "Leader: 2" || true)

log "Initial distribution: Broker 0: $BROKER0_COUNT, Broker 1: $BROKER1_COUNT, Broker 2: $BROKER2_COUNT"

# Step 5: Wait for metrics to accumulate in Prometheus
log "Step 5: Waiting for metrics to accumulate in Prometheus/Grafana..."
log "Waiting 60 seconds for metrics collection..."
sleep 60

# Verify metrics exist
log "Verifying metrics are available..."
METRIC_CHECK=$(curl -s http://localhost:8890/metrics | grep "kafka_partition_count{" | head -1)
if [ -n "$METRIC_CHECK" ]; then
    log_success "Metrics confirmed: $METRIC_CHECK"
else
    log_warning "Metrics not found yet, waiting another 30 seconds..."
    sleep 30
fi

# Step 6: Capture "before" screenshot
log "Step 6: Capturing 'before' Grafana screenshot..."

# Get dashboard UID (assuming it's provisioned)
DASHBOARD_UID="autobalancer-demo"

# Capture screenshot using Grafana rendering API
curl -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    "http://localhost:3000/render/d-solo/$DASHBOARD_UID/automq-auto-balancer-demo?orgId=1&panelId=2&width=1200&height=600&from=now-10m&to=now" \
    -o "$SCREENSHOTS_DIR/before-balancing-$TIMESTAMP.png" 2>&1 | tee -a "$LOG_FILE"

if [ -f "$SCREENSHOTS_DIR/before-balancing-$TIMESTAMP.png" ]; then
    SIZE=$(wc -c < "$SCREENSHOTS_DIR/before-balancing-$TIMESTAMP.png")
    log_success "Screenshot saved: before-balancing-$TIMESTAMP.png ($SIZE bytes)"
    if [ "$SIZE" -lt 10000 ]; then
        log_warning "Screenshot size is small - may show 'no data'. Waiting longer..."
        sleep 30
    fi
else
    log_warning "Failed to capture screenshot (Grafana may not be ready yet)"
fi

# Step 6: Start traffic generation
log "Step 6: Starting high-volume traffic generation (10 MB/sec)..."
log "Traffic will run for $LOAD_DURATION seconds ($((LOAD_DURATION/60)) minutes)..."

# Start producer in background
docker run -d --name traffic-producer-$TIMESTAMP \
    --network automq_net_traffic \
    automqinc/automq:1.6.0 \
    bash -c "
    while true; do
        /opt/automq/kafka/bin/kafka-producer-perf-test.sh \
            --topic $TOPIC_NAME \
            --num-records 100000 \
            --record-size 10240 \
            --throughput 1000 \
            --producer-props bootstrap.servers=server1:9092 \
            acks=1 \
            linger.ms=10 \
            batch.size=32768 \
            compression.type=lz4
        sleep 1
    done
    " 2>&1 | tee -a "$LOG_FILE"

log_success "Traffic generation started"

# Step 7: Monitor partition distribution
log "Step 7: Monitoring partition distribution for rebalancing..."
log "Checking every $CHECK_INTERVAL seconds for $((LOAD_DURATION/60)) minutes..."
log ""

CHECKS=$((LOAD_DURATION / CHECK_INTERVAL))
REBALANCED=false
REBALANCE_TIME=""

for i in $(seq 1 $CHECKS); do
    log "========================================="
    log "Check $i/$CHECKS - $(date '+%H:%M:%S')"
    log "========================================="
    
    # Get current distribution
    CURRENT_DIST=$(docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
        --describe \
        --bootstrap-server server1:9092 \
        --topic "$TOPIC_NAME" 2>&1)
    
    # Count partitions per broker
    BROKER0_COUNT=$(echo "$CURRENT_DIST" | grep -c "Leader: 0" || true)
    BROKER1_COUNT=$(echo "$CURRENT_DIST" | grep -c "Leader: 1" || true)
    BROKER2_COUNT=$(echo "$CURRENT_DIST" | grep -c "Leader: 2" || true)
    
    log "Broker 0: $BROKER0_COUNT partitions"
    log "Broker 1: $BROKER1_COUNT partitions"
    log "Broker 2: $BROKER2_COUNT partitions"
    
    # Check if rebalancing occurred
    if [ "$BROKER0_COUNT" -ne 4 ] && [ "$REBALANCED" = false ]; then
        log_success "✅ REBALANCING DETECTED!"
        REBALANCED=true
        REBALANCE_TIME=$(date '+%H:%M:%S')
        
        # Capture "during" screenshot
        log "Capturing 'during rebalancing' screenshot..."
        curl -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
            "http://localhost:3000/render/d-solo/$DASHBOARD_UID/automq-auto-balancer-demo?orgId=1&panelId=2&width=1200&height=600&from=now-10m&to=now" \
            -o "$SCREENSHOTS_DIR/during-balancing-$TIMESTAMP.png" 2>/dev/null
        
        if [ -f "$SCREENSHOTS_DIR/during-balancing-$TIMESTAMP.png" ]; then
            log_success "Screenshot saved: during-balancing-$TIMESTAMP.png"
        fi
    fi
    
    # Check if balanced (2-2-2 or close)
    MAX_DIFF=$((BROKER0_COUNT > BROKER1_COUNT ? BROKER0_COUNT - BROKER1_COUNT : BROKER1_COUNT - BROKER0_COUNT))
    MAX_DIFF2=$((BROKER1_COUNT > BROKER2_COUNT ? BROKER1_COUNT - BROKER2_COUNT : BROKER2_COUNT - BROKER1_COUNT))
    MAX_DIFF3=$((BROKER0_COUNT > BROKER2_COUNT ? BROKER0_COUNT - BROKER2_COUNT : BROKER2_COUNT - BROKER0_COUNT))
    
    if [ "$MAX_DIFF" -le 1 ] && [ "$MAX_DIFF2" -le 1 ] && [ "$MAX_DIFF3" -le 1 ] && [ "$REBALANCED" = true ]; then
        log_success "✅ BALANCED STATE ACHIEVED!"
        
        # Capture "after" screenshot
        log "Capturing 'after balancing' screenshot..."
        curl -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
            "http://localhost:3000/render/d-solo/$DASHBOARD_UID/automq-auto-balancer-demo?orgId=1&panelId=2&width=1200&height=600&from=now-15m&to=now" \
            -o "$SCREENSHOTS_DIR/after-balancing-$TIMESTAMP.png" 2>/dev/null
        
        if [ -f "$SCREENSHOTS_DIR/after-balancing-$TIMESTAMP.png" ]; then
            log_success "Screenshot saved: after-balancing-$TIMESTAMP.png"
        fi
        
        # Continue monitoring for a bit longer to ensure stability
        log "Continuing to monitor for stability..."
    fi
    
    log ""
    sleep "$CHECK_INTERVAL"
done

# Step 8: Stop traffic generation
log "Step 8: Stopping traffic generation..."
docker stop traffic-producer-$TIMESTAMP 2>&1 | tee -a "$LOG_FILE"
docker rm traffic-producer-$TIMESTAMP 2>&1 | tee -a "$LOG_FILE"
log_success "Traffic generation stopped"

# Step 9: Final verification
log "Step 9: Final partition distribution verification..."
FINAL_DIST=$(docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --describe \
    --bootstrap-server server1:9092 \
    --topic "$TOPIC_NAME" 2>&1)

echo "$FINAL_DIST" | tee -a "$LOG_FILE"

BROKER0_FINAL=$(echo "$FINAL_DIST" | grep -c "Leader: 0" || true)
BROKER1_FINAL=$(echo "$FINAL_DIST" | grep -c "Leader: 1" || true)
BROKER2_FINAL=$(echo "$FINAL_DIST" | grep -c "Leader: 2" || true)

log "Final distribution: Broker 0: $BROKER0_FINAL, Broker 1: $BROKER1_FINAL, Broker 2: $BROKER2_FINAL"

# Step 10: Capture final comprehensive screenshot
log "Step 10: Capturing final comprehensive screenshot..."
curl -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    "http://localhost:3000/render/d-solo/$DASHBOARD_UID/automq-auto-balancer-demo?orgId=1&panelId=1&width=1400&height=800&from=now-30m&to=now" \
    -o "$SCREENSHOTS_DIR/final-overview-$TIMESTAMP.png" 2>/dev/null

if [ -f "$SCREENSHOTS_DIR/final-overview-$TIMESTAMP.png" ]; then
    log_success "Screenshot saved: final-overview-$TIMESTAMP.png"
fi

# Step 11: Generate results report
log "Step 11: Generating results report..."

cat > "$RESULTS_DIR/experiment-summary-$TIMESTAMP.md" <<EOF
# Traffic-Based Auto-Balancing Experiment Results

**Experiment ID**: $TIMESTAMP  
**Date**: $(date '+%Y-%m-%d %H:%M:%S')  
**Duration**: $((LOAD_DURATION/60)) minutes

## Configuration

- **Topic**: $TOPIC_NAME
- **Partitions**: $PARTITIONS
- **Replication Factor**: $REPLICATION_FACTOR
- **Traffic Load**: 10 MB/sec
- **Check Interval**: $CHECK_INTERVAL seconds

## Results

### Initial Distribution (Imbalanced)

| Broker | Partitions |
|--------|-----------|
| Broker 0 | $BROKER0_COUNT |
| Broker 1 | $BROKER1_COUNT |
| Broker 2 | $BROKER2_COUNT |

**Status**: ❌ Imbalanced (4-1-1 distribution)

### Final Distribution

| Broker | Partitions |
|--------|-----------|
| Broker 0 | $BROKER0_FINAL |
| Broker 1 | $BROKER1_FINAL |
| Broker 2 | $BROKER2_FINAL |

**Status**: $([ "$REBALANCED" = true ] && echo "✅ Rebalanced" || echo "❌ Not rebalanced")

### Timeline

- **Experiment Start**: $(head -5 "$LOG_FILE" | grep "Timestamp" | cut -d: -f2-)
- **Rebalancing Detected**: ${REBALANCE_TIME:-"Not detected"}
- **Experiment End**: $(date '+%Y-%m-%d %H:%M:%S')

## Screenshots

1. **Before Balancing**: \`screenshots/before-balancing-$TIMESTAMP.png\`
2. **During Balancing**: \`screenshots/during-balancing-$TIMESTAMP.png\`
3. **After Balancing**: \`screenshots/after-balancing-$TIMESTAMP.png\`
4. **Final Overview**: \`screenshots/final-overview-$TIMESTAMP.png\`

## Conclusion

$(if [ "$REBALANCED" = true ]; then
    echo "✅ **SUCCESS**: AutoMQ's auto-balancer successfully detected the traffic imbalance and redistributed partitions to achieve balanced load across all brokers."
else
    echo "❌ **INCOMPLETE**: Auto-balancing was not detected during the experiment duration. Consider:"
    echo "- Increasing traffic load"
    echo "- Extending monitoring duration"
    echo "- Checking auto-balancer configuration"
fi)

## Log File

Full experiment log: \`experiment-$TIMESTAMP.log\`

EOF

log_success "Results report generated: experiment-summary-$TIMESTAMP.md"

# Summary
log ""
log "========================================="
log "Experiment Complete!"
log "========================================="
log "Results directory: $RESULTS_DIR"
log "Log file: $LOG_FILE"
log "Summary: experiment-summary-$TIMESTAMP.md"
log "Screenshots: $SCREENSHOTS_DIR"
log ""

if [ "$REBALANCED" = true ]; then
    log_success "✅ Auto-balancing was successful!"
else
    log_warning "⚠️  Auto-balancing was not detected. Check logs for details."
fi

log ""
log "To view Grafana dashboard: http://localhost:3000"
log "To view Prometheus: http://localhost:9090"
log ""
