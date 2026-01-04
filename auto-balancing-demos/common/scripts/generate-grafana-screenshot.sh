#!/bin/bash
# Generate screenshot from Grafana dashboard using API
# Usage: ./generate-grafana-screenshot.sh <dashboard_uid> <panel_id> <output_file> [time_range]

set -e

DASHBOARD_UID=$1
PANEL_ID=$2
OUTPUT_FILE=$3
TIME_RANGE=${4:-"now-10m"}  # Default: last 10 minutes
GRAFANA_URL=${GRAFANA_URL:-"http://localhost:3000"}
GRAFANA_USER=${GRAFANA_USER:-"admin"}
GRAFANA_PASSWORD=${GRAFANA_PASSWORD:-"admin"}

if [ -z "$DASHBOARD_UID" ] || [ -z "$PANEL_ID" ] || [ -z "$OUTPUT_FILE" ]; then
    echo "Usage: $0 <dashboard_uid> <panel_id> <output_file> [time_range]"
    echo "Example: $0 autobalancer-demo 2 screenshot.png now-10m"
    exit 1
fi

echo "Generating screenshot for dashboard '$DASHBOARD_UID', panel $PANEL_ID..."

# Create output directory if it doesn't exist
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Generate screenshot using Grafana rendering API
# Note: Using d-solo for single panel rendering
curl -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    "${GRAFANA_URL}/render/d-solo/${DASHBOARD_UID}/autobalancer-demo?orgId=1&panelId=${PANEL_ID}&width=1200&height=600&from=${TIME_RANGE}&to=now" \
    -o "$OUTPUT_FILE" \
    --fail \
    --silent \
    --show-error

# Verify the file was created and has content
if [ ! -f "$OUTPUT_FILE" ] || [ ! -s "$OUTPUT_FILE" ]; then
    echo "✗ Failed to generate screenshot"
    exit 1
fi

file_size=$(wc -c < "$OUTPUT_FILE")
echo "✓ Screenshot saved to $OUTPUT_FILE (${file_size} bytes)"
