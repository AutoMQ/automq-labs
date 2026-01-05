#!/bin/bash

# Quick test to verify screenshots work with actual data
# This is a 5-minute test version

set -e

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESULTS_DIR="../results"
SCREENSHOTS_DIR="$RESULTS_DIR/screenshots"
LOG_FILE="$RESULTS_DIR/quick-test-$TIMESTAMP.log"

mkdir -p "$RESULTS_DIR" "$SCREENSHOTS_DIR"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log "=== Quick Screenshot Test ==="
log "Timestamp: $TIMESTAMP"

# Start cluster
log "Starting cluster..."
cd ..
docker compose -f docker-compose-clean.yml up -d 2>&1 | tee -a "$LOG_FILE"

log "Waiting 40 seconds for services to start..."
sleep 40

# Wait for brokers
log "Waiting for brokers..."
for i in {1..20}; do
    if docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-broker-api-versions.sh \
        --bootstrap-server server1:9092 &>/dev/null; then
        log_success "Brokers ready!"
        break
    fi
    sleep 5
done

# Create topic
log "Creating topic..."
docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --create --bootstrap-server server1:9092 \
    --topic test-topic --partitions 6 --replication-factor 1 2>&1 | tee -a "$LOG_FILE"

sleep 10

# Create imbalanced distribution
log "Creating imbalanced distribution (4-1-1)..."
cat > /tmp/reassignment-test.json <<EOF
{
  "version": 1,
  "partitions": [
    {"topic": "test-topic", "partition": 0, "replicas": [0]},
    {"topic": "test-topic", "partition": 1, "replicas": [0]},
    {"topic": "test-topic", "partition": 2, "replicas": [0]},
    {"topic": "test-topic", "partition": 3, "replicas": [0]},
    {"topic": "test-topic", "partition": 4, "replicas": [1]},
    {"topic": "test-topic", "partition": 5, "replicas": [2]}
  ]
}
EOF

docker cp /tmp/reassignment-test.json automq-server1-traffic:/tmp/reassignment.json
docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-reassign-partitions.sh \
    --bootstrap-server server1:9092 --reassignment-json-file /tmp/reassignment.json --execute 2>&1 | tee -a "$LOG_FILE"

sleep 10

# Start traffic
log "Starting traffic generation..."
docker run -d --name test-producer-$TIMESTAMP \
    --network automq_net_traffic \
    automqinc/automq:1.6.0 \
    bash -c "
    while true; do
        /opt/automq/kafka/bin/kafka-producer-perf-test.sh \
            --topic test-topic \
            --num-records 50000 \
            --record-size 10240 \
            --throughput 1000 \
            --producer-props bootstrap.servers=server1:9092 acks=1 linger.ms=10 batch.size=32768
        sleep 1
    done
    " 2>&1 | tee -a "$LOG_FILE"

log_success "Traffic started"

# Wait for metrics to accumulate
log "Waiting 90 seconds for metrics to accumulate in Prometheus..."
sleep 90

# Check metrics
log "Checking metrics..."
METRICS=$(curl -s http://localhost:8890/metrics | grep "kafka_partition_count{" | head -3)
log "Sample metrics:"
echo "$METRICS" | tee -a "$LOG_FILE"

# Capture screenshot
log "Capturing screenshot..."
curl -u admin:admin \
    "http://localhost:3000/render/d-solo/autobalancer-demo/automq-auto-balancer-demo?orgId=1&panelId=2&width=1200&height=600&from=now-10m&to=now" \
    -o "$SCREENSHOTS_DIR/test-$TIMESTAMP.png" 2>&1 | tee -a "$LOG_FILE"

if [ -f "$SCREENSHOTS_DIR/test-$TIMESTAMP.png" ]; then
    SIZE=$(wc -c < "$SCREENSHOTS_DIR/test-$TIMESTAMP.png")
    log_success "Screenshot saved: $SIZE bytes"
    
    if [ "$SIZE" -gt 20000 ]; then
        log_success "✅ Screenshot size looks good - likely has data!"
    else
        log "⚠️  Screenshot is small ($SIZE bytes) - may show 'no data'"
    fi
    
    file "$SCREENSHOTS_DIR/test-$TIMESTAMP.png" | tee -a "$LOG_FILE"
else
    log "❌ Screenshot failed"
fi

# Cleanup
log "Stopping traffic..."
docker stop test-producer-$TIMESTAMP 2>&1 | tee -a "$LOG_FILE"
docker rm test-producer-$TIMESTAMP 2>&1 | tee -a "$LOG_FILE"

log ""
log_success "Test complete!"
log "Screenshot: $SCREENSHOTS_DIR/test-$TIMESTAMP.png"
log "Log: $LOG_FILE"
log ""
log "To view screenshot:"
log "  open $SCREENSHOTS_DIR/test-$TIMESTAMP.png"
