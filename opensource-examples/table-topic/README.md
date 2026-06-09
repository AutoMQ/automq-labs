# AutoMQ Table Topic Examples

This directory contains examples for AutoMQ Table Topic, which writes Kafka topic data into Apache Iceberg tables.

| Example | Description |
| --- | --- |
| [playground](playground/) | A full local Table Topic playground with MinIO, Iceberg REST Catalog, Schema Registry, Trino, and multiple ingestion scenarios. |
| [iceberg-spark-streaming](iceberg-spark-streaming/) | A streaming pipeline where AutoMQ writes a source Iceberg table and Spark Structured Streaming transforms it into another Iceberg table. |
| [hive-metastore-integration](hive-metastore-integration/) | A Table Topic example using Hive Metastore as the Iceberg catalog. |
| [oss-tablebucket-integration](oss-tablebucket-integration/) | A Table Topic example using Aliyun OSS Tables with both REST Catalog and TableBucket Catalog modes. |
