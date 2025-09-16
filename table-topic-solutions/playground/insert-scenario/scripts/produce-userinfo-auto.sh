#!/usr/bin/env bash
set -euo pipefail
TOPIC=${1:-UserInfo}
COUNT=${2:-10}
SCHEMA_REGISTRY_URL=${SCHEMA_REGISTRY_URL:-http://schema-registry:8081}
SCHEMA_FILE=${SCHEMA_FILE:-insert-scenario/schemas/UserInfo.avsc}

echo "[upsert] Producing $COUNT Avro messages to topic $TOPIC"
trap 'echo "[upsert] Failed to produce messages. Likely schema/JSON mismatch or Schema Registry unreachable." >&2' ERR

generate() {
  i=1
  while [ "$i" -le "$COUNT" ]; do
    printf '{"id":"u-%d","name":"user_%d","email":"user_%d@example.com"}\n' "$i" "$i" "$i"
    i=$((i+1))
  done
}

python3 tools/avro-gen/generate_from_avsc.py --schema "$SCHEMA_FILE" --count "$COUNT" \
  --template id=u-{i} --template name=user_{i} --template email=user_{i}@example.com \
  | docker exec -i kafka-client kafka-avro-console-producer \
    --bootstrap-server automq:9092 \
    --property "schema.registry.url=$SCHEMA_REGISTRY_URL" \
    --topic "$TOPIC" \
    --property "value.schema=$(tr -d '\n' < "$SCHEMA_FILE")"
