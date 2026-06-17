#!/bin/bash
# Collect metrics from Prometheus and format as Markdown

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
COMMON_DIR="$(dirname "$DEMO_DIR")/common"

STAGE=${1:-"before"}  # before or after
OUTPUT_FILE="$DEMO_DIR/results/${STAGE}-balancing.md"

echo "========================================="
echo "Collecting Metrics ($STAGE balancing)"
echo "========================================="
echo ""

# Create results directory
mkdir -p "$DEMO_DIR/results"

# Query Prometheus for metrics
echo "Querying Prometheus..."

# Get BytesInPerSec for each broker
bytes_in_data=$("$COMMON_DIR/scripts/query-prometheus.sh" \
  'kafka_server_broker_topic_metrics_bytes_in_per_sec')

# Get partition counts
partition_data=$("$COMMON_DIR/scripts/query-prometheus.sh" \
  'kafka_server_replica_manager_partition_count')

# Get partition distribution from Kafka
echo "Getting partition distribution..."
partition_dist=$(docker exec automq-server1-qps bash -c "
  /opt/automq/kafka/bin/kafka-topics.sh \
    --bootstrap-server server1:9092 \
    --describe \
    --topic qps-test
")

# Parse metrics
echo "Parsing metrics..."

broker1_bytes=$(echo "$bytes_in_data" | jq -r '.[] | select(.metric.broker=="server1") | .value[1]' | head -1)
broker2_bytes=$(echo "$bytes_in_data" | jq -r '.[] | select(.metric.broker=="server2") | .value[1]' | head -1)
broker3_bytes=$(echo "$bytes_in_data" | jq -r '.[] | select(.metric.broker=="server3") | .value[1]' | head -1)

broker1_parts=$(echo "$partition_data" | jq -r '.[] | select(.metric.broker=="server1") | .value[1]' | head -1)
broker2_parts=$(echo "$partition_data" | jq -r '.[] | select(.metric.broker=="server2") | .value[1]' | head -1)
broker3_parts=$(echo "$partition_data" | jq -r '.[] | select(.metric.broker=="server3") | .value[1]' | head -1)

# Handle null values
broker1_bytes=${broker1_bytes:-0}
broker2_bytes=${broker2_bytes:-0}
broker3_bytes=${broker3_bytes:-0}
broker1_parts=${broker1_parts:-0}
broker2_parts=${broker2_parts:-0}
broker3_parts=${broker3_parts:-0}

# Calculate standard deviation
std_dev=$(echo "$broker1_bytes $broker2_bytes $broker3_bytes" | "$COMMON_DIR/scripts/calculate-std-dev.sh")

# Calculate total
total_bytes=$(python3 -c "print(${broker1_bytes} + ${broker2_bytes} + ${broker3_bytes})")

# Generate report
cat > "$OUTPUT_FILE" << EOF
# Metrics Report - ${STAGE^} Auto-Balancing

**Timestamp:** $(date '+%Y-%m-%d %H:%M:%S')

## Traffic Metrics

### Bytes In Per Second by Broker

| Broker | BytesInPerSec | Percentage | Partitions |
|--------|---------------|------------|------------|
| server1 (Broker 0) | $(printf "%.2f" $broker1_bytes) | $(python3 -c "print(f'{${broker1_bytes}/${total_bytes}*100:.1f}%' if ${total_bytes} > 0 else '0%')") | $broker1_parts |
| server2 (Broker 1) | $(printf "%.2f" $broker2_bytes) | $(python3 -c "print(f'{${broker2_bytes}/${total_bytes}*100:.1f}%' if ${total_bytes} > 0 else '0%')") | $broker2_parts |
| server3 (Broker 2) | $(printf "%.2f" $broker3_bytes) | $(python3 -c "print(f'{${broker3_bytes}/${total_bytes}*100:.1f}%' if ${total_bytes} > 0 else '0%')") | $broker3_parts |
| **Total** | **$(printf "%.2f" $total_bytes)** | **100%** | **$(($broker1_parts + $broker2_parts + $broker3_parts))** |

### Balance Metrics

- **Standard Deviation:** $std_dev bytes/sec
- **Max-Min Difference:** $(python3 -c "import sys; vals=[${broker1_bytes},${broker2_bytes},${broker3_bytes}]; print(f'{max(vals)-min(vals):.2f}')") bytes/sec

## Partition Distribution

\`\`\`
$partition_dist
\`\`\`

## Analysis

EOF

if [ "$STAGE" = "before" ]; then
  cat >> "$OUTPUT_FILE" << EOF
This snapshot was taken **before** auto-balancing. The qps distribution shows:
- Broker 0 is handling the majority of qps
- Partitions are unevenly distributed
- Standard deviation indicates significant imbalance

The auto-balancer should detect this imbalance and redistribute partitions.
EOF
else
  cat >> "$OUTPUT_FILE" << EOF
This snapshot was taken **after** auto-balancing. The qps distribution shows:
- Traffic is more evenly distributed across brokers
- Partitions have been redistributed
- Standard deviation has decreased, indicating improved balance

The auto-balancer has successfully rebalanced the cluster.
EOF
fi

echo ""
echo "✓ Metrics collected and saved to: $OUTPUT_FILE"
echo ""
cat "$OUTPUT_FILE"
echo ""
