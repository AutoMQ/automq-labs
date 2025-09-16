#!/usr/bin/env bash
set -euo pipefail

TOPIC=${1:-product}
TYPE=${2:-product} # product | user

echo "[protobuf-raw] Producing Protobuf raw ($TYPE) to $TOPIC"

docker exec kafka-client python3 /home/kafka-client/sample/protobuf-sample/kafka_protobuf_producer.py "$TOPIC" "$TYPE"

