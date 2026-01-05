#!/bin/bash
# Generate Grafana screenshots

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
COMMON_DIR="$(dirname "$DEMO_DIR")/common"

STAGE=${1:-"after"}  # before or after
SCREENSHOT_DIR="$DEMO_DIR/results/screenshots"

echo "========================================="
echo "Generating Grafana Screenshots ($STAGE)"
echo "========================================="
echo ""

# Create screenshots directory
mkdir -p "$SCREENSHOT_DIR"

# Wait for Grafana to be ready
echo "Checking Grafana availability..."
max_attempts=30
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if curl -s -f http://localhost:3000/api/health > /dev/null 2>&1; then
        echo "✓ Grafana is ready"
        break
    fi
    echo "Waiting for Grafana... ($((attempt+1))/$max_attempts)"
    sleep 2
    attempt=$((attempt+1))
done

if [ $attempt -eq $max_attempts ]; then
    echo "✗ Grafana is not responding"
    exit 1
fi

# Set time range based on stage
if [ "$STAGE" = "before" ]; then
    TIME_RANGE="now-5m"
else
    TIME_RANGE="now-15m"
fi

echo ""
echo "Generating screenshots with time range: $TIME_RANGE to now"
echo ""

# Panel IDs from the dashboard
PANELS=(
    "2:bytes-in"
    "3:bytes-out"
    "4:messages-in"
    "5:partition-count"
    "6:produce-latency"
    "7:fetch-latency"
)

for panel_info in "${PANELS[@]}"; do
    IFS=':' read -r panel_id panel_name <<< "$panel_info"
    output_file="$SCREENSHOT_DIR/${STAGE}-${panel_name}.png"
    
    echo "Capturing panel $panel_id ($panel_name)..."
    
    "$COMMON_DIR/scripts/generate-grafana-screenshot.sh" \
        "autobalancer-demo" \
        "$panel_id" \
        "$output_file" \
        "$TIME_RANGE" || echo "  Warning: Failed to capture panel $panel_id"
done

echo ""
echo "========================================="
echo "✓ Screenshots Generated"
echo "========================================="
echo ""
echo "Screenshots saved to: $SCREENSHOT_DIR"
ls -lh "$SCREENSHOT_DIR"/${STAGE}-*.png 2>/dev/null || echo "No screenshots were generated"
echo ""
