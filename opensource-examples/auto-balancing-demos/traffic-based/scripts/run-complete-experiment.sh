#!/bin/bash
# Complete traffic-based auto-balancing experiment
# This script runs the ENTIRE experiment from start to finish with NO manual interaction

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$DEMO_DIR/results"

echo "=============================================="
echo "Traffic-Based Auto-Balancing - Full Experiment"
echo "=============================================="
echo ""
echo "This experiment will:"
echo "1. Start cluster and create topic"
echo "2. Create partition imbalance (4-1-1)"
echo "3. Generate screenshots BEFORE"
echo "4. Generate HIGH load on ALL 6 partitions (10 MB/sec)"
echo "5. Monitor for 20 minutes"
echo "6. Generate screenshots AFTER"
echo "7. Collect all results"
echo ""
echo "Expected result: 2-2-2 distribution"
echo ""

# Clean up previous results
echo ""
echo "Cleaning up previous results..."
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR/screenshots"
mkdir -p "$RESULTS_DIR/before"
mkdir -p "$RESULTS_DIR/after"

# Step 1: Setup cluster
echo ""
echo "========================================="
echo "Step 1: Starting Cluster"
echo "========================================="
bash "$SCRIPT_DIR/setup.sh"

# Step 2: Create imbalance
echo ""
echo "========================================="
echo "Step 2: Creating Partition Imbalance"
echo "========================================="
bash "$SCRIPT_DIR/create-imbalance.sh"

# Save initial distribution
docker exec automq-server1-traffic bash -c "
  unset KAFKA_JMX_OPTS
  /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 \
    --describe \
    --topic traffic-test
" | grep "Partition:" > "$RESULTS_DIR/before/partition-distribution.txt"

# Step 3: Generate BEFORE screenshots
echo ""
echo "========================================="
echo "Step 3: Generating BEFORE Screenshots"
echo "========================================="
bash "$SCRIPT_DIR/generate-screenshots.sh" before

# Step 4: Start high load on ALL 6 partitions
echo ""
echo "========================================="
echo "Step 4: Starting High Load (10 MB/sec)"
echo "========================================="
echo ""
echo "Starting load generation with RoundRobinPartitioner..."
echo "This ensures ALL 6 partitions receive equal load"
echo ""

# Start load generation in background
bash "$SCRIPT_DIR/high-load.sh" > "$RESULTS_DIR/load-generation.log" 2>&1 &
LOAD_PID=$!

echo "Load generation started (PID: $LOAD_PID)"
echo "Waiting 30 seconds for load to stabilize..."
sleep 30

# Step 5: Monitor for 20 minutes
echo ""
echo "========================================="
echo "Step 5: Monitoring (20 minutes)"
echo "========================================="
bash "$SCRIPT_DIR/monitor-20min.sh"

# Stop load generation
echo ""
echo "Stopping load generation..."
kill $LOAD_PID 2>/dev/null || true
pkill -P $LOAD_PID 2>/dev/null || true
sleep 5

# Step 6: Generate AFTER screenshots
echo ""
echo "========================================="
echo "Step 6: Generating AFTER Screenshots"
echo "========================================="
bash "$SCRIPT_DIR/generate-screenshots.sh" after

# Step 7: Collect results
echo ""
echo "========================================="
echo "Step 7: Collecting Results"
echo "========================================="

# Get final partition distribution
echo ""
echo "Final partition distribution:"
docker exec automq-server1-traffic bash -c "
  unset KAFKA_JMX_OPTS
  /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 \
    --describe \
    --topic traffic-test
" | grep "Partition:" | tee "$RESULTS_DIR/after/partition-distribution.txt"

# Count partitions per broker
echo ""
echo "Partition count per broker:"
BROKER0=$(grep "Partition:" "$RESULTS_DIR/after/partition-distribution.txt" | grep -c "Leader: 0" || echo "0")
BROKER1=$(grep "Partition:" "$RESULTS_DIR/after/partition-distribution.txt" | grep -c "Leader: 1" || echo "0")
BROKER2=$(grep "Partition:" "$RESULTS_DIR/after/partition-distribution.txt" | grep -c "Leader: 2" || echo "0")

echo "  Broker 0: $BROKER0 partitions"
echo "  Broker 1: $BROKER1 partitions"
echo "  Broker 2: $BROKER2 partitions"
echo "  Distribution: $BROKER0-$BROKER1-$BROKER2"

# Check if expected distribution achieved
if [ "$BROKER0" -eq 2 ] && [ "$BROKER1" -eq 2 ] && [ "$BROKER2" -eq 2 ]; then
    echo ""
    echo "✅ SUCCESS: Expected 2-2-2 distribution achieved!"
    RESULT="SUCCESS"
else
    echo ""
    echo "⚠️  UNEXPECTED: Got $BROKER0-$BROKER1-$BROKER2, expected 2-2-2"
    RESULT="PARTIAL - Auto-balancer triggered but distribution differs from expected"
fi

# Verify screenshots
BEFORE_COUNT=$(ls -1 "$RESULTS_DIR/screenshots/before-"*.png 2>/dev/null | wc -l | tr -d ' ')
AFTER_COUNT=$(ls -1 "$RESULTS_DIR/screenshots/after-"*.png 2>/dev/null | wc -l | tr -d ' ')

echo ""
echo "Screenshots generated:"
echo "  Before: $BEFORE_COUNT files"
echo "  After: $AFTER_COUNT files"

if [ "$BEFORE_COUNT" -ge 6 ] && [ "$AFTER_COUNT" -ge 6 ]; then
    echo "  ✅ All screenshots generated successfully"
else
    echo "  ⚠️  Some screenshots may be missing"
fi

# Generate summary
cat > "$RESULTS_DIR/experiment-summary.txt" <<EOF
Traffic-Based Auto-Balancing Experiment
Date: $(date)

Initial Distribution: 4-1-1 (Broker 0: 4, Broker 1: 1, Broker 2: 1)
Final Distribution: $BROKER0-$BROKER1-$BROKER2
Expected Distribution: 2-2-2

Load Configuration:
- RoundRobinPartitioner (ensures all 6 partitions loaded)
- 1000 records/sec total
- 10KB per record
- Total: ~10 MB/sec
- Duration: 20 minutes

Result: $RESULT

Screenshots:
- Before: $BEFORE_COUNT files
- After: $AFTER_COUNT files

Monitoring Log: rebalancing-progress.log
Load Log: load-generation.log
EOF

echo ""
echo "========================================="
echo "✓ Experiment Complete"
echo "========================================="
echo ""
cat "$RESULTS_DIR/experiment-summary.txt"
echo ""
echo "All results saved to: $RESULTS_DIR"
echo ""
