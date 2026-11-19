#!/bin/bash
# Monitor auto-balancer behavior during high QPS load

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$DEMO_DIR/results"

mkdir -p "$RESULTS_DIR"

DURATION=1200  # 20 minutes
INTERVAL=30    # Check every 30 seconds
CHECKS=$((DURATION / INTERVAL))

LOG_FILE="$RESULTS_DIR/high-qps-rebalancing.log"

echo "==========================================="  | tee "$LOG_FILE"
echo "Monitoring Auto-Balancer for $DURATION seconds (20 minutes)" | tee -a "$LOG_FILE"
echo "Checks: $CHECKS (every $INTERVAL seconds)" | tee -a "$LOG_FILE"
echo "==========================================="  | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

for i in $(seq 1 $CHECKS); do
  echo "Check $i/$CHECKS at $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
  echo "-------------------------------------------" | tee -a "$LOG_FILE"
  
  docker exec automq-server1-qps bash -c "
    unset KAFKA_JMX_OPTS
    /opt/automq/kafka/bin/kafka-topics.sh \
      --bootstrap-server server1:9092 \
      --describe \
      --topic qps-test
  " 2>/dev/null | tee -a "$LOG_FILE"
  
  echo "" | tee -a "$LOG_FILE"
  
  sleep $INTERVAL
done

echo "==========================================="  | tee -a "$LOG_FILE"
echo "Monitoring Complete" | tee -a "$LOG_FILE"
echo "==========================================="  | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "Results saved to: $LOG_FILE"
