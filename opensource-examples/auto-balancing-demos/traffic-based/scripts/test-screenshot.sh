#!/bin/bash

# Test script to verify Grafana screenshots work correctly

set -e

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SCREENSHOTS_DIR="../results/screenshots-test"
mkdir -p "$SCREENSHOTS_DIR"

echo "=== Testing Grafana Screenshot Capture ==="
echo "Timestamp: $TIMESTAMP"
echo ""

# Wait for brokers
echo "Waiting for brokers to be ready..."
for i in {1..30}; do
    if docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-broker-api-versions.sh \
        --bootstrap-server server1:9092 &>/dev/null; then
        echo "✅ Brokers ready!"
        break
    fi
    sleep 5
done

# Create topic
echo "Creating test topic..."
docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-topics.sh \
    --create --bootstrap-server server1:9092 \
    --topic screenshot-test --partitions 6 --replication-factor 1 2>&1 || echo "Topic may already exist"

sleep 5

# Generate some traffic to create metrics
echo "Generating traffic to create metrics..."
docker exec automq-server1-traffic /opt/automq/kafka/bin/kafka-producer-perf-test.sh \
    --topic screenshot-test \
    --num-records 10000 \
    --record-size 1024 \
    --throughput 1000 \
    --producer-props bootstrap.servers=server1:9092 acks=1 &

sleep 30

# Check if metrics exist in Prometheus
echo ""
echo "Checking Prometheus metrics..."
curl -s "http://localhost:9090/api/v1/query?query=kafka_partition_count" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['status'] == 'success' and len(data['data']['result']) > 0:
    print('✅ Metrics found in Prometheus:')
    for result in data['data']['result']:
        print(f\"  - {result['metric'].get('instance', 'unknown')}: {result['value'][1]} partitions\")
else:
    print('❌ No metrics found in Prometheus')
    sys.exit(1)
"

echo ""
echo "Waiting 30 more seconds for metrics to accumulate..."
sleep 30

# Test screenshot capture
echo ""
echo "Capturing test screenshot..."
curl -u admin:admin \
    "http://localhost:3000/render/d-solo/autobalancer-demo/automq-auto-balancer-demo?orgId=1&panelId=2&width=1200&height=600&from=now-5m&to=now" \
    -o "$SCREENSHOTS_DIR/test-$TIMESTAMP.png" 2>&1

if [ -f "$SCREENSHOTS_DIR/test-$TIMESTAMP.png" ]; then
    SIZE=$(wc -c < "$SCREENSHOTS_DIR/test-$TIMESTAMP.png")
    echo "✅ Screenshot saved: test-$TIMESTAMP.png ($SIZE bytes)"
    
    # Check if it's a valid PNG
    if file "$SCREENSHOTS_DIR/test-$TIMESTAMP.png" | grep -q "PNG image"; then
        echo "✅ Valid PNG image"
        
        # Check size - if too small, likely "no data"
        if [ "$SIZE" -lt 5000 ]; then
            echo "⚠️  WARNING: Screenshot is very small ($SIZE bytes) - may show 'no data'"
        else
            echo "✅ Screenshot size looks good ($SIZE bytes)"
        fi
    else
        echo "❌ Not a valid PNG image"
    fi
else
    echo "❌ Screenshot not created"
fi

echo ""
echo "Test complete. Check $SCREENSHOTS_DIR/test-$TIMESTAMP.png"
echo ""
echo "To view in browser:"
echo "  open $SCREENSHOTS_DIR/test-$TIMESTAMP.png"
