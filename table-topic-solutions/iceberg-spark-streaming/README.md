# AutoMQ with Iceberg and Spark Structured Streaming Example

This document guides you through setting up and running a real-time data streaming pipeline using `AutoMQ`, `Apache Iceberg`, and `Spark Structured Streaming`.

This example demonstrates the following process and features:
1.  A `producer` service sends vehicle telemetry data in JSON format to an `AutoMQ` topic.
2.  The topic has the schemaless `Table Topic` feature enabled, automatically ingesting data into a source Iceberg table. This table has a schema of `(key, value, timestamp)` and is partitioned by the message timestamp.
3.  A `Spark Structured Streaming` job reads from this source Iceberg table in real-time.
4.  The job parses the JSON-formatted `value` field, flattens its structure, and streams the transformed data into a new, well-structured destination Iceberg table.

## Docker Compose Components

This demo environment is orchestrated using `Docker Compose` and includes the following services:

*   **`producer`**: A custom Python application that creates a topic and sends JSON-formatted vehicle telemetry data to `AutoMQ`.
*   **`automq`**: A single-node `AutoMQ` instance configured to use the `Iceberg REST Catalog` and `Minio` for storage.
*   **`spark-iceberg`**: A `Spark` container with all the necessary dependencies for running `Spark Structured Streaming` with `Iceberg` integration. It is used to submit streaming jobs via `spark-submit` and perform ad-hoc queries via `pyspark`.
*   **`rest`**: The `Iceberg REST Catalog` service, providing a centralized metadata layer for `Iceberg` tables.
*   **`minio`**: An `S3`-compatible object storage service used for all `Iceberg` data and `AutoMQ` stream data.
*   **`mc`**: The `Minio` client, used to initialize the required `S3` buckets (`warehouse`, `automq-data`, `automq-ops`) on startup.

## Justfile Commands Overview

A `justfile` is provided to simplify common operations.

*   `just up`: Builds images (if necessary) and starts all services in the background.
*   `just down`: Stops and removes all containers.
*   `just logs`: Tails the logs for all services.
*   `just create-topic`: Creates the source `Kafka topic` with `Table Topic` configuration.
*   `just write`: Runs the `producer` to continuously send messages.
*   `just submit-job`: Submits the `Spark Structured Streaming` job.
*   `just shell`: Opens an interactive `PySpark` shell pre-configured for `Iceberg` and `S3` connections.

## Usage Guide

### Prerequisites

Ensure you have the `just` command-line tool installed. If not, you can install it using `Homebrew` (macOS) or another package manager:
```sh
brew install just
```

Follow these steps to run the end-to-end data pipeline.

### Step 1: Start the Environment

Use the `just` command to build and start all services.

```sh
just up
```

### Step 2: Create the Topic

Create a source `topic` named `telemetry` and enable the schemaless `Table Topic` feature for it.

```sh
just create-topic
```

### Step 3: Send Test Messages

Open a new terminal window and run the `producer` to send sample vehicle data to the `topic`.

```sh
# Sends messages continuously. Press Ctrl+C to stop.
just write
```

### Step 4: Submit the Spark Streaming Job

Submit the `Spark` job. This job reads from the source table, transforms the data, and writes it to the processed destination table (`vehicle`).

```sh
# Press Ctrl+C to stop.
just submit-job
```

### Step 5: Query the Results

After sending some data, you can query the source and destination `Iceberg` tables to verify the data flow.

1.  **Open a `PySpark` shell:**
    ```sh
    just shell
    ```

2.  **Execute queries in the `PySpark shell`:**

    *   **Query the raw source table:**
        You will see the original `Kafka` message format, where the `value` field is in binary format.
        ```python
        spark.sql("""SELECT * FROM default.telemetry LIMIT 10""").show(truncate=False)
        ```

    *   **Query the processed destination table:**
        You will see the structured data with the `JSON` fields expanded.
        ```python
        spark.sql("SELECT * FROM default.vehicle LIMIT 10").show()
        ```

### Step 6: Clean Up the Environment

When you are finished, use the following command to stop and clean up all resources.

```sh
just down
```


