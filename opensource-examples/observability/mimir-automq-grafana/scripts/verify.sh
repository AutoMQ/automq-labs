#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

wait_http() {
  local name="$1"
  local url="$2"
  local attempts="${3:-60}"

  printf "Checking %-24s %s\n" "$name" "$url"
  for _ in $(seq 1 "$attempts"); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      echo "  ok"
      return 0
    fi
    sleep 2
  done

  echo "  failed"
  return 1
}

docker compose ps

echo
docker compose exec -T kafka-client \
  /opt/automq/kafka/bin/kafka-broker-api-versions.sh \
  --bootstrap-server automq:9092 >/dev/null
echo "AutoMQ Kafka API: ok"

docker compose exec -T kafka-client \
  /opt/automq/kafka/bin/kafka-topics.sh \
  --bootstrap-server automq:9092 \
  --describe --topic mimir-ingest || true

echo
wait_http "Mimir distributor" "http://localhost:9009/ready"
wait_http "Mimir query-frontend" "http://localhost:9010/ready"
wait_http "Grafana" "http://localhost:3000/api/health"
wait_http "Prometheus" "http://localhost:9091/-/ready"

echo
echo "Querying Mimir for a Prometheus self metric..."
curl -fsS --get "http://localhost:9010/prometheus/api/v1/query" \
  --data-urlencode 'query=up' | sed 's/,/,\n/g' | head -n 20

echo
echo "Querying Mimir through the Grafana datasource proxy..."
grafana_response="$(
  curl -fsS --get "http://localhost:3000/api/datasources/proxy/uid/mimir/api/v1/query" \
    --data-urlencode 'query=up'
)"
echo "$grafana_response" | sed 's/,/,\n/g' | head -n 20

if ! echo "$grafana_response" | grep -q '"result":\['; then
  echo "Grafana datasource query did not return a vector result."
  exit 1
fi

if echo "$grafana_response" | grep -q '"result":\[\]'; then
  echo "Grafana datasource query returned no series. Wait for Prometheus to scrape and remote-write samples, then retry."
  exit 1
fi

echo
echo "Verification complete."
