#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

INGESTER="${1:-mimir-ingester-zone-a-0}"

echo "Stopping ${INGESTER} for 45 seconds."
docker compose stop "$INGESTER"

echo
echo "The distributor should continue acknowledging writes after AutoMQ persists them."
echo "The other zone owner can keep recent queries available for partition 0."
echo

for i in $(seq 1 9); do
  curl -fsS --get "http://localhost:9010/prometheus/api/v1/query" \
    --data-urlencode 'query=sum(rate(prometheus_remote_storage_samples_total[1m]))' >/dev/null || true
  printf "."
  sleep 5
done

echo
echo "Restarting ${INGESTER}."
docker compose start "$INGESTER"

echo
echo "Recent ingest-reader logs:"
docker compose logs --since=3m "$INGESTER" | tail -n 80 || true

echo
echo "Run 'just verify' after the ingester is ready, then watch the replay-delay and ingester consumption panels in Grafana."
