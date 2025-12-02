# Scenario: Real-Time GitHub Events Analytics

## 1. Scenario Objective

This scenario demonstrates how to build a real-time analytics pipeline for GitHub events using AutoMQ Table Topic. It ingests public GitHub timeline events from [GH Archive](https://www.gharchive.org/), automatically converts them into Apache Iceberg tables, and provides real-time analytics through a Marimo notebook interface.

The solution showcases:
- **Streaming Data Ingestion**: Continuously pulling GitHub events from GH Archive (starting from 3 days ago, keeping up with data up to 3 hours ago)
- **Automatic Table Conversion**: Using AutoMQ Table Topic to automatically transform Kafka topics into Iceberg tables
- **Real-Time Analytics**: Interactive dashboard with live statistics, top repositories, and recent events
- **No ETL Required**: Direct querying of Iceberg tables via Spark SQL without traditional ETL pipelines

## 2. Architecture Overview

```
GH Archive → Producer → AutoMQ Kafka → Table Topic → Iceberg Table → Spark/Marimo
```

1. **Producer**: Continuously fetches GitHub events from GH Archive and sends them to Kafka
2. **AutoMQ Table Topic**: Automatically converts the Kafka topic into an Iceberg table
3. **Marimo Notebook**: Provides an interactive dashboard for real-time analytics
4. **Spark SQL**: Enables direct querying of the Iceberg table

## 3. Quick Start

### Run Full Test Scenario

The easiest way to experience the complete scenario is to run the automated test:

```bash
just -f github-event/justfile test
```

This command will:
1. Start all services (including topic creation)
2. Wait for data processing (60 seconds)
3. Query and verify data ingestion
4. Clean up all resources

## 4. Step-by-Step Guide

### Step 1: Start All Services

This command starts the producer and Marimo notebook. It also automatically creates the required Kafka topic.

```bash
just -f github-event/justfile up
```

This will:
- Create the `github_events_iceberg` Table Topic
- Start the producer (which begins pulling data from GH Archive)
- Start the Marimo notebook server

**Note**: The producer runs continuously, pulling data from 3 days ago and keeping up with data up to 3 hours ago.

### Step 2: Access Marimo Dashboard

Once services are started, access the interactive dashboard at:

```
http://localhost:2718
```

The dashboard provides:
- **Recent Stars (3 days)**: Count of WatchEvents in the last 3 days
- **Total Events (3 days)**: Total number of events in the last 3 days
- **Top 10 Repositories by Stars**: Most starred repositories in the last 3 days
- **Recent GitHub Events**: Latest 20 events with auto-refresh every 60 seconds

### Step 3: Query Data via Spark SQL

Query the Iceberg table directly using Spark SQL:

```bash
just -f github-event/justfile query
```

This will show the 20 most recent events from the table.

### Step 4: Individual Service Management

You can also manage services individually:

```bash
# Create topic only
just -f github-event/justfile topic-create

# Start producer only
just -f github-event/justfile producer-up

# Start Marimo only
just -f github-event/justfile marimo-up
```

## 5. Data Flow

### Producer Behavior

The producer (`event_producer.py`) is designed to run continuously:

1. **Initial Load**: Starts pulling data from 3 days ago (UTC)
2. **Continuous Sync**: Keeps pulling data up to 3 hours ago (to account for GH Archive data availability)
3. **Data Processing**: Downloads hourly archives, decompresses, transforms to Avro format, and sends to Kafka
4. **Error Handling**: Automatically retries on failures and handles 404 errors (data not yet available)

### Table Topic Configuration

The `github_events_iceberg` topic is configured as a Table Topic, which means:
- Messages are automatically converted to Iceberg table format
- Schema is managed via Schema Registry
- Data is queryable via Spark SQL and Trino immediately

### Data Schema

The GitHub events are flattened into the following schema:
- `id`: Event ID
- `type`: Event type (e.g., WatchEvent, PushEvent, etc.)
- `created_at`: Timestamp in milliseconds
- `actor_login`: GitHub username of the actor
- `repo_name`: Repository name (e.g., "owner/repo")

## 6. Expected Outcome

1. **Iceberg Table Creation**: An Iceberg table named `default.github_events_iceberg` is automatically created
2. **Continuous Data Ingestion**: GitHub events are continuously ingested from GH Archive
3. **Real-Time Analytics**: The Marimo dashboard shows live statistics that refresh every 60 seconds
4. **Query Capability**: Data can be queried directly via Spark SQL or Trino without ETL

## 7. Monitoring and Debugging

### Check Producer Logs

```bash
docker logs -f github-event-producer
```

The producer logs include:
- Connection status to Kafka and Schema Registry
- Processing progress for each hour of data
- Event sending statistics (success/failure counts)
- Performance metrics (events per second)

### Check Marimo Logs

```bash
docker logs -f github-event-marimo
```

### Query Table Statistics

You can query the table to verify data ingestion:

```bash
# Count total events
just spark-sql "SELECT COUNT(*) FROM default.github_events_iceberg"

# Count WatchEvents (stars)
just spark-sql "SELECT COUNT(*) FROM default.github_events_iceberg WHERE type = 'WatchEvent'"

# Top repositories by stars
just spark-sql "SELECT repo_name, COUNT(*) as stars FROM default.github_events_iceberg WHERE type = 'WatchEvent' GROUP BY repo_name ORDER BY stars DESC LIMIT 10"
```

## 8. Cleanup

Stop and remove all services:

```bash
just -f github-event/justfile down
```

## 9. Learn More

- [AutoMQ Table Topic Documentation](https://github.com/AutoMQ/automq)
- [GH Archive](https://www.gharchive.org/) - Public GitHub timeline events
- [Marimo](https://marimo.io/) - Reactive Python notebooks
- [Apache Iceberg](https://iceberg.apache.org/) - Open table format for large analytics tables

