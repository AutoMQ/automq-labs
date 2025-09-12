# Scenario: Upsert Ingestion with Primary Key

## 1. Scenario Objective

This scenario demonstrates how to stream Avro records into an Iceberg table with a primary key, enabling **upsert** functionality. When a new record arrives with a primary key that already exists in the table, the old record is replaced with the new one.

## 2. Core Configuration

This scenario relies on the following key Table Topic configurations to handle upserts:
- `automq.table.topic.convert.value.type=by_schema_id` (see root README “Common Configuration”)
- `automq.table.topic.transform.value.type=flatten` (see root README “Common Configuration”)
- `automq.table.topic.id.columns=[id]`: Specifies the primary key column (`id`) used to identify rows for updates.
- `automq.table.topic.upsert.enable=true`: Enables the upsert behavior, where new data for an existing primary key replaces the old data.

## 3. Steps to Run

Follow these steps to run the demonstration.

### Step 1: Start Services

This command starts the base services required for the scenario.

```bash
just up
```

### Step 2: Create Table Topic

This command creates a Table Topic named `user-info` with the required upsert configuration.

```bash
just -f insert-scenario/justfile create-topic
```

### Step 3: Produce Initial Data

This command produces an initial batch of user records and sends them to the `user-info` topic.

```bash
just -f insert-scenario/justfile send-auto
```

### Step 4: Update an Existing Record

This command sends a new record for an existing user (`id='u-1'`), which will trigger an upsert operation.

```bash
just -f insert-scenario/justfile update-one
```

### Step 5: View Table Info

Inspect table metadata and definition.

```bash
just -f insert-scenario/justfile show-ddl
just -f insert-scenario/justfile show-snapshots
just -f insert-scenario/justfile show-history
just -f insert-scenario/justfile show-files
just -f insert-scenario/justfile show-manifests
```

### Step 6: Query Iceberg Data

Query the Iceberg table via Trino to see the result of the upsert. The record for `id='u-1'` will be updated.

```bash
just -f insert-scenario/justfile query
```

## 4. Expected Outcome

1.  **Iceberg Table Creation**: An Iceberg table named `user-info` is created in the `iceberg.default` database with a primary key defined on the `id` column.
2.  **Initial Data Ingestion**: The first batch of user records is ingested into the table.
3.  **Upsert Behavior**: The `update-one` command triggers an equality delete for the old record with `id='u-1'` and appends the new record, effectively replacing it.
4.  **Query Verification**: Queries against the Iceberg table in Trino show the latest state for each user. The record for `id='u-1'` reflects the updated information.

## 5. Cleanup

Run the following command to stop and remove all Docker containers started for this scenario.

```bash
just down
```
