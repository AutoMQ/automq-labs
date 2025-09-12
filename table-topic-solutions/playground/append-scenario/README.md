# Scenario: Append-Only Ingestion

## 1. Scenario Objective

This scenario demonstrates how to stream Avro records into an Iceberg table using an **append-only** ingestion pattern. The server leverages Schema Registry to decode Avro messages and maps the Kafka record value fields into table columns before writing to Iceberg.

## 2. Core Configuration

This scenario relies on the following key Table Topic configurations (see root README “Common Configuration” for details):

- `automq.table.topic.convert.value.type=by_schema_id`
- `automq.table.topic.transform.value.type=flatten`

## 3. Steps to Run

This scenario demonstrates: write with the initial schema, then upgrade the schema and continue writing, and finally observe Iceberg's automatic schema evolution in the table.

### Step 1: Start Services

This command starts the base services required for the scenario, including Kafka, Schema Registry, and Trino.

```bash
just up
```

### Step 2: Create Table Topic

This command creates a Table Topic named `orders` with the required append-only configuration.

```bash
just -f append-scenario/justfile create-topic
```

### Step 3: Produce Initial Data (Schema v1)

Generate Avro data based on `schemas/Order.avsc` and send it to `orders`.

```bash
just -f append-scenario/justfile send-auto
```

### Step 4: View Table Info

Inspect table metadata and definition.

```bash
just -f append-scenario/justfile show-ddl
just -f append-scenario/justfile show-snapshots
just -f append-scenario/justfile show-history
just -f append-scenario/justfile show-files
just -f append-scenario/justfile show-manifests
```

### Step 5: Produce Data with Evolved Schema (Aggregated)

Register and write data using a single evolved schema that aggregates common compatible changes:
- Add a new field `price: double` (with default)
- Make `order_description` optional (nullable)
- Add `quantity: long` (with default)

The evolved schema is at `schemas/OrderV2.avsc`.

```bash
just -f append-scenario/justfile send-auto-v2
```

### Step 6: View Table Info Again

```bash
just -f append-scenario/justfile show-ddl
just -f append-scenario/justfile show-snapshots
just -f append-scenario/justfile show-history
just -f append-scenario/justfile show-files
just -f append-scenario/justfile show-manifests
```

### Step 7: Query Iceberg Data

Query the table to see all records across versions.

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
