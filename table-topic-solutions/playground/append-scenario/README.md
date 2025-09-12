# Scenario: Append-Only Ingestion

## 1. Scenario Objective

This scenario demonstrates how to stream Avro records into an Iceberg table using an **append-only** ingestion pattern. The server leverages Schema Registry to decode Avro messages and flattens the nested structure before writing to Iceberg.

## 2. Core Configuration

This scenario relies on the following key Table Topic configurations to handle simple append-only ingestion:

- `automq.table.topic.convert.value.type=by_schema_id`: Decode the Avro message using its schema in Schema Registry.
- `automq.table.topic.transform.value.type=flatten`: Flatten the Kafka value payload into table columns (nested structures → columns).

## 3. Steps to Run

Follow these steps to run the demonstration.

### Step 1: Start Services

This command starts the base services required for the scenario, including Kafka, Schema Registry, and Trino.

```bash
just up
```

### Step 2: Create Table Topic

This command creates a Table Topic named `order` with the required append-only configuration.

```bash
just -f append-scenario/justfile create-topic
```

### Step 3: Produce Data

This command automatically generates Avro-formatted data based on the `schemas/Order.avsc` file and sends it to the `order` topic.

```bash
just -f append-scenario/justfile send-auto
```

### Step 4: Query Iceberg Data

Query the Iceberg table via Trino to see the ingested data.

```bash
just -f append-scenario/justfile query
```

## 4. Expected Outcome

1.  **Iceberg Table Creation**: An Iceberg table named `order` is automatically created in the `iceberg.default` database.
2.  **Data Ingestion**: Data sent by the `send-auto` command is successfully written to the `order` table in an append-only fashion.
3.  **Query Verification**: Queries against the Iceberg table in Trino show the newly appended rows after each production step.

## 5. Cleanup

Run the following command to stop and remove all Docker containers started for this scenario.

```bash
just down
```
