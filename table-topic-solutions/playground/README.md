# AutoMQ Table Topic Playground

This playground provides a collection of hands-on labs to help you learn how to stream data from Kafka topics into Apache Iceberg tables in real-time using the AutoMQ Table Topic feature.

## 1. Getting Started

Please ensure you have `docker` and `just` installed on your system.

### Step 1: Start the Services

Run the following command to start all the necessary background services, including AutoMQ, Schema Registry, Trino, and MinIO.

```bash
just up
```

### Step 2: Choose a Scenario

Navigate to the directory of a scenario you are interested in and follow the instructions in its `README.md` file. Each scenario is designed to demonstrate a specific capability.

## 2. Core Scenarios

This project includes the following core scenarios. Each is self-contained in its own directory with a detailed guide.

| Scenario | Directory | Core Feature | Description |
| :--- | :--- | :--- | :--- |
| **CDC Ingestion** | `cdc-scenario/` | `Debezium CDC` | Demonstrates capturing row-level changes (INSERT/UPDATE/DELETE) from MySQL using Debezium and automatically syncing them to an Iceberg table. |
| **Append-Only Ingestion** | `append-scenario/` | `Append-Only` | A basic scenario showing how to stream Avro data into an Iceberg table in an append-only pattern. |
| **Upsert Ingestion** | `insert-scenario/` | `Upsert` | Demonstrates how to perform real-time updates (upserts) on an Iceberg table based on a primary key. |
| **Partitioned Table** | `partition-scenario/` | `Partitioning` | Shows how to create a partitioned table to optimize query performance and how to query partition metadata. |
| **Protobuf Ingestion** | `protobuf-latest-scenario/` | `Protobuf` | Demonstrates ingesting raw Protobuf messages using server-side decoding, without a client-side Schema Registry serializer. |

## 3. Common Commands

The root `justfile` provides several common commands for managing and interacting with the environment.

- **Check service status**: `just status`
- **View service logs**: `just logs` or `just logs <service_name>`
- **Execute a Trino SQL query**: `just trino-sql "SHOW TABLES FROM iceberg.default"`
- **List all topics**: `just topic-list`
- **Describe a topic**: `just topic-describe <topic_name>`

## 4. Core Component Stack

This playground is composed of the following services, all running in Docker containers:

- **automq**: A Kafka-compatible message broker with the built-in Table Topic feature for writing to Iceberg.
- **schema-registry**: Confluent Schema Registry for storing and managing Avro/Protobuf schemas.
- **minio**: An S3-compatible object storage service used as the warehouse for Iceberg tables.
- **rest**: The Iceberg REST Catalog service for managing Iceberg table metadata.
- **trino**: A high-performance, distributed SQL query engine for querying data in Iceberg.
- **kafka-client**: A client container with Kafka command-line tools and data production scripts.

## 5. Cleanup

After you have finished your experiments, you can run the following command to stop and remove all related Docker containers, freeing up system resources.

```bash
just down
```