#!/usr/bin/env bash
set -euo pipefail
TOPIC=${1:-OrderWithTs}
COUNT=${2:-10}
SCHEMA_REGISTRY_URL=${SCHEMA_REGISTRY_URL:-http://schema-registry:8081}
SCHEMA_FILE=${SCHEMA_FILE:-partition-scenario/schemas/OrderWithTs.avsc}

echo "[partition] Producing $COUNT Avro messages with ts to topic $TOPIC"
trap 'echo "[partition] Failed to produce messages. Likely schema/JSON mismatch or Schema Registry unreachable." >&2' ERR

python3 tools/avro-gen/generate_from_avsc.py --schema "$SCHEMA_FILE" --count "$COUNT" \
  | docker exec -i kafka-client kafka-avro-console-producer \
  --bootstrap-server automq:9092 \
  --property "schema.registry.url=$SCHEMA_REGISTRY_URL" \
  --topic "$TOPIC" \
  --property "value.schema=$(tr -d '\n' < "$SCHEMA_FILE")"
