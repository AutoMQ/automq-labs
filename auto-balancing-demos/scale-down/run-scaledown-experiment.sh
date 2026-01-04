#!/bin/bash

# Scale-Down Auto-Balancing Experiment
# Demonstrates auto-balancer redistributing partitions when a broker is removed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
SCREENSHOTS_DIR="$RESULTS_DIR/screenshots"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$RESULTS_DIR/experiment-$TIMESTAMP.log"

BOOTSTRAP_SERVER="localhost:9092"
TOPIC_NAME="scaledown-test"
PARTITIONS=12
LOAD_DURATION=900
CHECK_INTERVAL=30
GRAFANA_URL="http://localhost:3030"
GRAFANA_USER="admin"
GRAFANA_PASSWORD="admin"
DASHBOARD_UID="autobalancer-demo"
PANEL_ID=2

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
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
        
        # Check if container is running before querying
        if docker ps --format '{{.Names}}' | grep -q "automq-server${i}-scaledown"; then
            # Get partition count for user topics (excluding system topics)
            local partition_count=$(docker exec automq-server${i}-scaledown curl -s http://localhost:8890/metrics 2>/dev/null | \
                grep "kafka_log_end_offset{" | grep -v "__" | grep "topic=\"$TOPIC_NAME\"" | wc -l | tr -d ' ')
            
            echo "Broker $broker_id: $partition_count partitions" >> "$metrics_log"
            distribution="${distribution}${partition_count} "
            
            # Log to console
            log "  Broker $broker_id: $partition_count partitions"
        else
            echo "Broker $broker_id: 0 partitions (stopped)" >> "$metrics_log"
            distribution="${distribution}0 "
            log "  Broker $broker_id: 0 partitions (stopped)"
        fi
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
            # Check if container is running before querying
            if docker ps --format '{{.Names}}' | grep -q "automq-server${i}-scaledown"; then
                local partition_count=$(docker exec automq-server${i}-scaledown curl -s http://localhost:8890/metrics 2>/dev/null | \
                    grep "kafka_log_end_offset{" | grep -v "__" | grep "topic=\"$TOPIC_NAME\"" | wc -l | tr -d ' ')
                current_distribution="${current_distribution}${partition_count}-"
            else
                current_distribution="${current_distribution}0-"
            fi
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

mkdir -p "$RESULTS_DIR" "$SCREENSHOTS_DIR"

log "========================================="
log "Scale-Down Auto-Balancing Experiment"
log "========================================="

# Clean up any existing environment
log "Cleaning up existing environment..."
cd "$SCRIPT_DIR"
docker compose -f docker-compose-with-metrics.yml down -v 2>&1 | tee -a "$LOG_FILE" || true
sleep 5

# Remove network if it exists
docker network rm automq_net_scaledown 2>/dev/null || true

# Start cluster with 3 brokers
log "Starting cluster with 3 brokers..."
docker compose -f docker-compose-with-metrics.yml up -d 2>&1 | tee -a "$LOG_FILE"
sleep 30

# Wait for brokers
log "Waiting for brokers..."
for i in {1..30}; do
    if docker exec automq-server1-scaledown /opt/automq/kafka/bin/kafka-broker-api-versions.sh \
        --bootstrap-server server1:9092 &>/dev/null; then
        log_success "Brokers ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        log_error "Brokers failed to start"
        exit 1
    fi
    sleep 10
done

# Wait for Grafana
log "Waiting for Grafana to be ready..."
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

# Create topic
log "Creating topic with $PARTITIONS partitions..."
# Delete topic if it exists from a previous run
docker exec automq-server1-scaledown /opt/automq/kafka/bin/kafka-topics.sh \
    --delete --bootstrap-server server1:9092 \
    --topic "$TOPIC_NAME" 2>&1 | tee -a "$LOG_FILE" || true

log "Waiting 10 seconds for topic deletion to complete..."
sleep 10

docker exec automq-server1-scaledown /opt/automq/kafka/bin/kafka-topics.sh \
    --create --bootstrap-server server1:9092 \
    --topic "$TOPIC_NAME" --partitions "$PARTITIONS" --replication-factor 1 2>&1 | tee -a "$LOG_FILE"

log "Waiting 15 seconds for topic to be fully created..."
sleep 15

# Verify initial distribution (should be 4-4-4)
log "Initial partition distribution (3 brokers):"
INITIAL_DIST=$(docker exec automq-server1-scaledown /opt/automq/kafka/bin/kafka-topics.sh \
    --describe --bootstrap-server server1:9092 --topic "$TOPIC_NAME" 2>&1)
echo "$INITIAL_DIST" | tee -a "$LOG_FILE"

B0_INITIAL=$(echo "$INITIAL_DIST" | grep -c "Leader: 0" || true)
B1_INITIAL=$(echo "$INITIAL_DIST" | grep -c "Leader: 1" || true)
B2_INITIAL=$(echo "$INITIAL_DIST" | grep -c "Leader: 2" || true)

log "Broker 0: $B0_INITIAL, Broker 1: $B1_INITIAL, Broker 2: $B2_INITIAL"

# Wait for metrics to accumulate
log "Waiting 60 seconds for metrics to accumulate..."
sleep 60

# Capture before screenshot
capture_screenshot "01-before-scaledown"

# Start traffic
log "Starting traffic..."
docker run -d --name scaledown-producer-$TIMESTAMP \
    --network automq_net_scaledown \
    automqinc/automq:1.6.0 \
    bash -c "
    while true; do
        /opt/automq/kafka/bin/kafka-producer-perf-test.sh \
            --topic $TOPIC_NAME \
            --num-records 100000 \
            --record-size 10240 \
            --throughput 1000 \
            --producer-props bootstrap.servers=server1:9092 acks=1 linger.ms=10 batch.size=32768
        sleep 1
    done
    " 2>&1 | tee -a "$LOG_FILE"

log_success "Traffic started"
sleep 10

# Stop broker 3 (scale down!)
log "⬇️  SCALING DOWN - Stopping Broker 2..."
docker stop automq-server3-scaledown 2>&1 | tee -a "$LOG_FILE"

SCALEDOWN_TIME=$(date '+%H:%M:%S')
log_error "Broker 2 stopped at $SCALEDOWN_TIME"

# Monitor for partition redistribution
log "Monitoring for partition redistribution..."
CHECKS=$((LOAD_DURATION / CHECK_INTERVAL))
REDISTRIBUTED=false

for i in $(seq 1 $CHECKS); do
    log "Check $i/$CHECKS - $(date '+%H:%M:%S')"
    
    DIST=$(docker exec automq-server1-scaledown /opt/automq/kafka/bin/kafka-topics.sh \
        --describe --bootstrap-server server1:9092 --topic "$TOPIC_NAME" 2>&1)
    
    B0=$(echo "$DIST" | grep -c "Leader: 0" || true)
    B1=$(echo "$DIST" | grep -c "Leader: 1" || true)
    B2=$(echo "$DIST" | grep -c "Leader: 2" || true)
    
    log "Broker 0: $B0, Broker 1: $B1, Broker 2 (STOPPED): $B2"
    
    # Check if partitions moved off broker 2
    if [ "$B2" -eq 0 ] && [ "$REDISTRIBUTED" = false ]; then
        log_success "✅ REDISTRIBUTION DETECTED! All partitions moved off stopped broker"
        log "Distribution: $B0-$B1-0 (was $B0_INITIAL-$B1_INITIAL-$B2_INITIAL)"
        REDISTRIBUTED=true
        
        sleep 30
        capture_screenshot "02-redistribution-detected"
    fi
    
    # Check if balanced across remaining 2 brokers
    if [ "$B2" -eq 0 ] && [ "$REDISTRIBUTED" = true ]; then
        DIFF=$((B0 > B1 ? B0 - B1 : B1 - B0))
        if [ "$DIFF" -le 1 ]; then
            log_success "✅ BALANCED! Partitions evenly distributed across remaining brokers"
            
            # Capture final balanced state immediately
            sleep 30
            capture_screenshot "03-final-balanced"
            
            # Stop traffic immediately after screenshot
            log "Stopping traffic..."
            docker stop scaledown-producer-$TIMESTAMP 2>&1 | tee -a "$LOG_FILE"
            docker rm scaledown-producer-$TIMESTAMP 2>&1 | tee -a "$LOG_FILE"
            
            break
        fi
    fi
    
    sleep "$CHECK_INTERVAL"
done

# Only stop traffic if not already stopped
if docker ps --format '{{.Names}}' | grep -q "scaledown-producer-$TIMESTAMP"; then
    log "Stopping traffic..."
    docker stop scaledown-producer-$TIMESTAMP 2>&1 | tee -a "$LOG_FILE"
    docker rm scaledown-producer-$TIMESTAMP 2>&1 | tee -a "$LOG_FILE"
fi

# Final verification
log "Final partition distribution (2 brokers):"
FINAL_DIST=$(docker exec automq-server1-scaledown /opt/automq/kafka/bin/kafka-topics.sh \
    --describe --bootstrap-server server1:9092 --topic "$TOPIC_NAME" 2>&1)
echo "$FINAL_DIST" | tee -a "$LOG_FILE"

B0_FINAL=$(echo "$FINAL_DIST" | grep -c "Leader: 0" || true)
B1_FINAL=$(echo "$FINAL_DIST" | grep -c "Leader: 1" || true)

log "Final: Broker 0: $B0_FINAL, Broker 1: $B1_FINAL"

log ""
log "========================================="
log "Scale-Down Experiment Complete!"
log "========================================="
log "Results directory: $RESULTS_DIR"
log "Screenshots directory: $SCREENSHOTS_DIR"
log "Log file: $LOG_FILE"
log ""

# List screenshots
log "Screenshots captured:"
ls -lh "$SCREENSHOTS_DIR"/*-${TIMESTAMP}.png 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' | tee -a "$LOG_FILE"

log ""
if [ "$REDISTRIBUTED" = true ]; then
    log_success "✅ Auto-balancer successfully redistributed partitions after scale-down"
else
    log_error "⚠️  Redistribution not detected - check logs"
fi

log ""
log "To clean up: docker compose -f docker-compose-with-metrics.yml down -v"
