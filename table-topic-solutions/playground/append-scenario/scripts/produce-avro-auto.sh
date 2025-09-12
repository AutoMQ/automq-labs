#!/usr/bin/env bash
set -euo pipefail

TOPIC=${1:-Order}
COUNT=${2:-10}
SCHEMA_REGISTRY_URL=${SCHEMA_REGISTRY_URL:-http://schema-registry:8081}
SCHEMA_FILE=${SCHEMA_FILE:-append-scenario/schemas/Order.avsc}

echo "[append] Producing $COUNT Avro messages to topic $TOPIC (auto-register)"
trap 'echo "[append] Failed to produce messages. Likely schema/JSON mismatch or Schema Registry unreachable." >&2' ERR

generate() {
  i=1
  while [ "$i" -le "$COUNT" ]; do
    printf '{"order_id":"o-%d","product_name":"item_%d","order_description":"desc_%d"}\n' "$i" "$i" "$i"
    i=$((i+1))
  done
}

python3 tools/avro-gen/generate_from_avsc.py --schema "$SCHEMA_FILE" --count "$COUNT" \
  | docker exec -i kafka-client kafka-avro-console-producer \
  --bootstrap-server automq:9092 \
  --property "schema.registry.url=$SCHEMA_REGISTRY_URL" \
  --topic "$TOPIC" \
  --property "value.schema=$(tr -d '\n' < "$SCHEMA_FILE")"
