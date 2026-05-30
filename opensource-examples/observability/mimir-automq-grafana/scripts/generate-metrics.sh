#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "Prometheus is already scraping local targets and remote_write sends those samples to Mimir."
echo "This command creates short extra query traffic so the dashboard has visible read-path activity."

for i in $(seq 1 30); do
  curl -fsS --get "http://localhost:9010/prometheus/api/v1/query" \
    --data-urlencode 'query=sum(rate(prometheus_tsdb_head_samples_appended_total[1m]))' >/dev/null
  printf "."
  sleep 1
done

echo
echo "Done. Open http://localhost:3000/d/mimir-automq-lab"
