# AutoMQ Table Topic Playground

Welcome to the AutoMQ Table Topic Playground!

This repository provides a collection of hands-on labs designed to help you master streaming data from Kafka topics into Apache Iceberg tables in real-time using AutoMQ's built-in **Table Topic** feature. No external data integration services like Flink or Spark are required.



## 1. Prerequisites

Before you begin, ensure you have the following installed on your system:

- `docker`: To run all the containerized services.
- `just`: A convenient command runner to simplify operations.

## 2. Quick Start

### Step 1: Start All Services

Run the following command to start all background services, including AutoMQ, Schema Registry, Trino, and MinIO.

```bash
just up
```

### Step 2: Explore a Scenario

Navigate to a scenario directory you are interested in (e.g., `append-scenario/`) and follow the instructions in its `README.md` file. Each scenario is designed to demonstrate a specific capability.

## 3. Core Scenarios

This project includes the following core scenarios. Each is self-contained in its own directory with a detailed guide.

| Scenario | Directory | Core Feature | Description |
| :--- | :--- | :--- | :--- |
| **Append-Only Ingestion** | `append-scenario/` | `Append-Only` | A basic scenario showing how to stream Avro data into an Iceberg table in an append-only pattern. |
| **Upsert Ingestion** | `insert-scenario/` | `Upsert` | Demonstrates how to perform real-time updates (upserts) on an Iceberg table based on a primary key. |
| **Partitioned Table** | `partition-scenario/` | `Partitioning` | Shows how to create a partitioned table to optimize query performance and how to query partition metadata. |
| **CDC Ingestion** | `cdc-scenario/` | `Debezium CDC` | Demonstrates capturing row-level changes (INSERT/UPDATE/DELETE) from MySQL using Debezium and automatically syncing them to an Iceberg table. |
| **Protobuf Ingestion** | `protobuf-latest-scenario/` | `Protobuf` | Demonstrates ingesting raw Protobuf messages using server-side decoding, without a client-side Schema Registry serializer. |

## 4. Common Commands (`just`)

The root `justfile` provides a set of commands to manage the environment and interact with its services.

### Environment Lifecycle

- **Start environment**: `just up`
- **Stop and clean up environment**: `just down`
- **Check service status**: `just status`
- **View service logs**: `just logs` or `just logs <service_name>`

### Topic Management

- **Create a Table Topic**: `just topic-create-table topic=<name> [convert_type] [transform_type]`
  - *Example (Avro by schema id + flatten)*: `just topic-create-table topic=orders convert_type=by_schema_id transform_type=flatten`
- **List all topics**: `just topic-list`
- **Describe a topic**: `just topic-describe <topic_name>`

### Querying Data

- **Query with Trino**: `just trino-sql "SHOW TABLES FROM iceberg.default"`
  - *Ideal for fast, ad-hoc queries and browsing metadata tables (e.g., `<table>$snapshots`).*
- **Query with Spark SQL**: `just spark-sql "<SQL>"`
  - *Useful for checking Spark semantics or compatibility.*
- **Launch an interactive PySpark shell**: `just pyspark`
  - *Comes pre-configured with Iceberg and S3A dependencies.*

> **Tip**: Run `just` in the project root to see all available commands and their descriptions.

## 5. Component Stack

This playground is composed of the following services, all running in Docker containers:

- **automq**: A Kafka-compatible message broker with the built-in Table Topic feature for writing to Iceberg.
- **schema-registry**: Confluent Schema Registry for storing and managing Avro/Protobuf schemas.
- **minio**: An S3-compatible object storage service used as the warehouse for Iceberg tables.
- **rest**: The Iceberg REST Catalog service for managing Iceberg table metadata.
- **trino**: A high-performance, distributed SQL query engine for querying data in Iceberg.
- **kafka-client**: A client container with Kafka command-line tools and data production scripts.

## 6. Cleanup

After you have finished your experiments, you can run the following command to stop and remove all related Docker containers, freeing up system resources.

```bash
just down
```