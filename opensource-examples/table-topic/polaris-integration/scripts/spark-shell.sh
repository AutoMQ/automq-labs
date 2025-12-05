#!/usr/bin/env bash
set -euo pipefail
/opt/bitnami/spark/bin/spark-shell \
  --conf spark.sql.catalog.iceberg=org.apache.iceberg.spark.SparkCatalog \
  --conf spark.sql.catalog.iceberg.type=hadoop \
  --conf spark.sql.catalog.iceberg.warehouse=s3a://warehouse \
  -i /workspace/scripts/init-iceberg.sql
