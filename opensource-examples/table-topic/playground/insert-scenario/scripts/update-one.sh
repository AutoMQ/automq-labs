#!/usr/bin/env bash
set -euo pipefail
TOPIC=${1:-UserInfo}
ID=${2:-u-1}
SCHEMA_REGISTRY_URL=${SCHEMA_REGISTRY_URL:-http://schema-registry:8081}
SCHEMA_FILE=${SCHEMA_FILE:-insert-scenario/schemas/UserInfo.avsc}

echo "[upsert] Updating id=$ID on topic $TOPIC"
trap 'echo "[upsert] Failed to update message. Likely schema/JSON mismatch or Schema Registry unreachable." >&2' ERR

python3 tools/avro-gen/generate_from_avsc.py --schema "$SCHEMA_FILE" --count 1 \
  --template "id=$ID" --template name=user_updated --template email=updated@example.com \
  | docker exec -i kafka-client kafka-avro-console-producer \
      --bootstrap-server automq:9092 \
      --property "schema.registry.url=$SCHEMA_REGISTRY_URL" \
      --topic "$TOPIC" \
      --property "value.schema=$(tr -d '\n' < "$SCHEMA_FILE")"
