#!/bin/bash
# Wait for auto-balancer to complete by monitoring standard deviation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")/common"

THRESHOLD=1000000  # 1MB/s standard deviation threshold
TIMEOUT=600  # 10 minutes
CHECK_INTERVAL=15  # Check every 15 seconds

echo "========================================="
echo "Waiting for Auto-Balancer to Complete"
echo "========================================="
echo ""
echo "Monitoring BytesInPerSec standard deviation..."
echo "Target: < $THRESHOLD bytes/sec"
echo "Timeout: $TIMEOUT seconds"
echo ""

elapsed=0
while [ $elapsed -lt $TIMEOUT ]; do
    # Query current metrics
    bytes_in_data=$("$COMMON_DIR/scripts/query-prometheus.sh" \
      'kafka_server_broker_topic_metrics_bytes_in_per_sec' 2>/dev/null || echo "[]")
    
    # Extract values
    broker1=$(echo "$bytes_in_data" | jq -r '.[] | select(.metric.broker=="server1") | .value[1]' | head -1)
    broker2=$(echo "$bytes_in_data" | jq -r '.[] | select(.metric.broker=="server2") | .value[1]' | head -1)
    broker3=$(echo "$bytes_in_data" | jq -r '.[] | select(.metric.broker=="server3") | .value[1]' | head -1)
    
    # Handle null values
    broker1=${broker1:-0}
    broker2=${broker2:-0}
    broker3=${broker3:-0}
    
    # Calculate standard deviation
    std_dev=$(echo "$broker1 $broker2 $broker3" | "$COMMON_DIR/scripts/calculate-std-dev.sh")
    std_dev_num=$(echo "$std_dev" | tr -d '[:space:]')
    
    echo "[$(date '+%H:%M:%S')] Broker1: $(printf "%.0f" $broker1) | Broker2: $(printf "%.0f" $broker2) | Broker3: $(printf "%.0f" $broker3) | StdDev: $std_dev"
    
    # Check if balanced
    if (( $(echo "$std_dev_num < $THRESHOLD" | bc -l) )); then
        echo ""
        echo "========================================="
        echo "✓ Auto-Balancer Complete!"
        echo "========================================="
        echo ""
        echo "Standard deviation is now below threshold: $std_dev < $THRESHOLD"
        echo "The cluster is balanced."
        echo ""
        exit 0
    fi
    
    sleep $CHECK_INTERVAL
    elapsed=$((elapsed + CHECK_INTERVAL))
done

echo ""
echo "========================================="
echo "⚠ Timeout Reached"
echo "========================================="
echo ""
echo "Auto-balancer did not complete within $TIMEOUT seconds."
echo "Current standard deviation: $std_dev"
echo ""
echo "This may be normal if:"
echo "  - The imbalance is not severe enough to trigger rebalancing"
echo "  - Auto-balancer is still in progress"
echo "  - Auto-balancer configuration needs adjustment"
echo ""
echo "Check broker logs for auto-balancer activity:"
echo "  docker compose logs server1 | grep autobalancer"
echo ""
exit 1
