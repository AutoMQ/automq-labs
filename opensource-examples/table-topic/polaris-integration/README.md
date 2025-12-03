# Apache Polaris Integration with AutoMQ Table Topic

This guide shows how to run AutoMQ Table Topic with Apache Polaris (Iceberg REST) using custom headers for realm routing and auth.

## Overview
- AutoMQ Table Topic type: `rest`
- Required headers: `Polaris-Realm`, `Authorization`
- Header config pattern: `automq.table.topic.catalog.header.{HeaderName}={Value}`

## Directory Structure
- docker-compose.yml: Polaris + MinIO + Spark + AutoMQ
- configs/
  - automq.properties
  - polaris.yaml
- scripts/
  - init-iceberg.sql
  - spark-shell.sh

## Quick start
1) Bring up stack
```bash
docker compose up -d --build
```

2) Verify Polaris REST
```bash
curl -s -H "Polaris-Realm=POLARIS" -H "Authorization=Bearer test-token" http://localhost:8181/v1/config
```

3) Create a Table Topic and write
```bash
# inside automq container network
kafka-topics.sh --bootstrap-server automq:9092 --create --topic tt.orders --partitions 3 --replication-factor 1
kafka-producer-perf-test.sh \
  --topic tt.orders --num-records 10000 --throughput -1 --record-size 512 \
  --producer-props bootstrap.servers=automq:9092 linger.ms=50
```

## AutoMQ config (configs/automq.properties)
```properties
automq.table.topic.enabled=true
automq.table.topic.catalog.type=rest
automq.table.topic.catalog.uri=http://polaris:8181
# Custom headers
automq.table.topic.catalog.header.Authorization=Bearer test-token
automq.table.topic.catalog.header.Polaris-Realm=POLARIS
# Optional
automq.table.topic.catalog.namespace=default
```

## Polaris config (configs/polaris.yaml)
Minimal dev setup with realm header enabled.
```yaml
server:
  applicationConnectors:
    - type: http
      port: 8181
polaris:
  realms:
    allowedRealms: ["POLARIS"]
  realmContext:
    requireHeader: true
    headerName: "Polaris-Realm"
security:
  auth:
    type: "fixed"
    token: "test-token"
```

## docker-compose.yml
Services: MinIO, Polaris, AutoMQ, Spark.
```yaml
version: "3.9"
services:
  minio:
    image: minio/minio:RELEASE.2024-09-22T00-00-00Z
    command: server /data --console-address :9001
    environment:
      MINIO_ROOT_USER: minio
      MINIO_ROOT_PASSWORD: minio123
    ports: ["9000:9000","9001:9001"]

  polaris:
    image: apache/polaris:1.1.0
    ports: ["8181:8181"]
    volumes:
      - ./configs/polaris.yaml:/opt/polaris/config.yaml:ro
    command: ["/opt/polaris/bin/polaris", "server", "-c", "/opt/polaris/config.yaml"]

  automq:
    image: automqinc/automq:latest
    depends_on: [minio, polaris]
    environment:
      AWS_REGION: us-east-1
      AWS_ACCESS_KEY_ID: minio
      AWS_SECRET_ACCESS_KEY: minio123
      AWS_ENDPOINT_OVERRIDE: http://minio:9000
      AUTOMQ_CONFIG: /opt/automq/automq.properties
    volumes:
      - ./configs/automq.properties:/opt/automq/automq.properties:ro
    ports: ["9092:9092"]

  spark:
    image: bitnami/spark:3.5
    depends_on: [polaris]
    environment:
      - SPARK_MODE=client
    volumes:
      - ./scripts:/workspace/scripts:ro
```

## Validate headers end-to-end
- Polaris access logs should show `Polaris-Realm` present
- AutoMQ logs should include REST catalog calls without errors

## Troubleshooting
- 404 from Polaris: realm header missing or value not in allowed list
- 401 from Polaris: invalid `Authorization`
- Table reads fail in Spark: confirm Iceberg REST catalog points to Polaris and headers are propagated
