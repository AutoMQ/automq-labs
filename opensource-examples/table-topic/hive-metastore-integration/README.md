# AutoMQ Iceberg Table Topic Demo

This project demonstrates a complete data pipeline using Docker Compose. It showcases how to send Avro-serialized messages from a Go producer to an AutoMQ (Kafka-compatible) topic, which then automatically writes the data into an Iceberg table. The data can then be queried using Trino.

## Architecture & Components

The `docker-compose.yaml` sets up the following services:

- **go-producer**: A Go container with a CLI to create Kafka topics and produce Avro-schema messages.
- **automq**: A Kafka-compatible message queue that persists data directly into S3-compatible storage. It's configured to automatically create Iceberg tables from topics.
- **schema-registry**: Confluent Schema Registry to manage Avro schemas for message serialization and deserialization.
- **trino**: A distributed SQL query engine used to query the Iceberg tables created by AutoMQ.
- **hive-metastore**: Stores the metadata for the Iceberg tables (schemas, partitions, etc.). It uses a MySQL database for its backend.
- **mysql**: The database for the Hive Metastore.
- **storage (MinIO)**: An S3-compatible object storage service where AutoMQ stores the actual data for the Iceberg tables.
- **mc (MinIO Client)**: A command-line client used to initialize buckets in MinIO.


## How to Use

### 1. Start the Environment

First, build and start all the services using Docker Compose.

```bash
docker compose up -d
```

When the services start, the `go-producer` container will be ready to accept commands. You will now manually create the topic.

```bash
docker compose run --rm go-producer /root/go-producer create-topic
```
You should see a message like "Topic 'web_page_view_events' created successfully."

### 2. Send Test Messages

Now, you can send some sample messages to the topic. The following command will send 15 messages to the topic.

```bash
docker compose run --rm go-producer /root/go-producer send-messages 15
```
You should see a confirmation that messages have been written.

### 3. Query the Data with Trino

After the messages are sent, AutoMQ will commit them to the Iceberg table within a few seconds (defined by `commit.interval.ms`). You can then use Trino to query the data.

First, connect to the Trino CLI:
```bash
docker compose exec trino trino
```

Once inside the Trino shell, you can run SQL queries:

```sql
-- Show available catalogs
SHOW CATALOGS;
--> You should see 'iceberg' among them.

-- Show schemas in the iceberg catalog
SHOW SCHEMAS FROM iceberg;
--> You should see 'default'.

-- Show tables in the schema
SHOW TABLES FROM iceberg.default;
--> You should see 'web_page_view_events'.

-- Describe the table schema
DESCRIBE iceberg.default.web_page_view_events;

-- Finally, query the data
SELECT user_id, page_url, ip_address FROM iceberg.default.web_page_view_events LIMIT 10;
```

This will return the data from the messages you sent in the previous step, confirming that the entire pipeline is working correctly.
