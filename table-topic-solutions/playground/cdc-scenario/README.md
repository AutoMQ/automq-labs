# Scenario: CDC Ingestion from MySQL

## 1. Scenario Objective

This scenario demonstrates an end-to-end Change Data Capture (CDC) pipeline. It captures row-level changes (INSERT, UPDATE, DELETE) from a MySQL database using Debezium and ingests them into a corresponding Iceberg table.

## 2. Core Configuration

This scenario relies on the following key Table Topic configurations to handle CDC events:

- `automq.table.topic.convert.value.type=by_schema_id`: Decodes the Avro message sent by Debezium using its schema from Schema Registry.
- `automq.table.topic.transform.value.type=flatten_debezium`: A specialized transformer that extracts the row state from the Debezium envelope and adds a `_cdc.op` field to mark the operation type (e.g., 'c' for create, 'u' for update, 'd' for delete).
- `automq.table.topic.id.columns=[id]`: Specifies the primary key column(s) used to identify rows for updates and deletes.
- `automq.table.topic.cdc.field=_cdc.op`: Tells the system which field contains the CDC operation type.

## 3. Steps to Run

Follow these steps to run the demonstration.

### Step 1: Start Services

This command starts the full CDC stack, including MySQL, Kafka Connect, Schema Registry, and other base services.

```bash
just -f cdc-scenario/justfile up
```

### Step 2: Create Table Topic

This command creates a Table Topic named `demo.sampledb.users` with the required CDC configuration.

```bash
just -f cdc-scenario/justfile create-table-topic
```

### Step 3: Deploy Debezium Connector

This deploys the Debezium MySQL connector, which starts monitoring the `users` table and sending change events to the Kafka topic.

```bash
just -f cdc-scenario/justfile create-avro-connector
```

### Step 4: Perform Database Operations

You can now perform DML operations in MySQL. The changes will be captured and reflected in the Iceberg table.

```bash
# Insert a random user
just -f cdc-scenario/justfile insert-random

# Update a random user
just -f cdc-scenario/justfile update-random

# Delete a random user
just -f cdc-scenario/justfile delete-random
```

### Step 5: View Table Info

Inspect table metadata and definition.

```bash
just -f cdc-scenario/justfile show-table-ddl
just -f cdc-scenario/justfile show-table-snapshots
just -f cdc-scenario/justfile show-table-history
just -f cdc-scenario/justfile show-table-files
```

### Step 6: Query Iceberg Data

Query the Iceberg table via Trino to see the merged results of the CDC operations.

```bash
just -f cdc-scenario/justfile query-table
```

## 4. Expected Outcome

1.  **Iceberg Table Creation**: An Iceberg table named `demo.sampledb.users` is created in the `iceberg.default` database, capable of handling CDC events.
2.  **Change Capture**: DML operations performed in MySQL are captured by Debezium and sent to the `demo.sampledb.users` Kafka topic.
3.  **Data Merging**: The Table Topic service processes these events, applying inserts, updates (upserts), and deletes to the Iceberg table.
4.  **Query Verification**: Queries against the Iceberg table in Trino show the latest state of the data, reflecting all the changes made in MySQL.

## 5. Cleanup

Run the following command to stop and remove all Docker containers started for this scenario.

```bash
just -f cdc-scenario/justfile down
```
