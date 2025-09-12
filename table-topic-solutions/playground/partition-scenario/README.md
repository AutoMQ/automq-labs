# Scenario: Partitioned Ingestion

## 1. Scenario Objective

This scenario demonstrates how to ingest data into a **partitioned** Iceberg table. Partitioning is a key optimization strategy that organizes data in the storage layer based on the values of one or more columns, which can significantly improve query performance by allowing query engines to prune (skip) irrelevant data files.

## 2. Core Configuration

This scenario relies on the following key Table Topic configurations to create a partitioned table:
- `automq.table.topic.convert.value.type=by_schema_id`
- `automq.table.topic.transform.value.type=flatten`
- `automq.table.topic.partition.by=[month(ts)]`: Defines the partitioning strategy. In this case, the table will be partitioned by the month extracted from the `ts` (timestamp) column.

## 3. Steps to Run

Follow these steps to run the demonstration.

### Step 1: Start Services

This command starts the base services required for the scenario.

```bash
just up
```

### Step 2: Create Table Topic

This command creates a Table Topic named `order-with-ts` with the specified monthly partitioning configuration.

```bash
just -f partition-scenario/justfile create-topic
```

### Step 3: Produce Initial Data

This command produces Avro records containing a timestamp field and sends them to the `order-with-ts` topic.

```bash
just -f partition-scenario/justfile send-auto
```

### Step 4: Inspect Current Partitioning & Table Info

Check current topic configuration, Iceberg partitions, and the table DDL.

```bash
# Show current topic config (includes partition.by)
just -f partition-scenario/justfile show-topic-config

# Show the partitions that have been created so far
just -f partition-scenario/justfile show-partitions

# Show the current table DDL and other metadata
just -f partition-scenario/justfile show-ddl
just -f partition-scenario/justfile show-snapshots
just -f partition-scenario/justfile show-history
just -f partition-scenario/justfile show-files
just -f partition-scenario/justfile show-manifests
```

### Step 5: Evolve Partition Spec (Iceberg)

Add a new Iceberg partition by modifying the topic configuration `automq.table.topic.partition.by`. The target partition spec is fixed in the scenario `justfile`.

```bash
just -f partition-scenario/justfile add-iceberg-partition
```

### Step 6: Produce More Data

Produce another batch of records so that new data is written using the updated partition spec.

```bash
just -f partition-scenario/justfile send-auto
```

### Step 7: Inspect After Change

Check topic config, partitions, and DDL again to observe the changes.

```bash
just -f partition-scenario/justfile show-topic-config
just -f partition-scenario/justfile show-partitions
just -f partition-scenario/justfile show-ddl
just -f partition-scenario/justfile show-snapshots
just -f partition-scenario/justfile show-history
just -f partition-scenario/justfile show-files
just -f partition-scenario/justfile show-manifests
```

### Step 8: Query Data

Query the data from the table.

```bash
just -f partition-scenario/justfile query
```

## 4. Expected Outcome

1.  **Partitioned Table Creation**: An Iceberg table named `order-with-ts` is created in the `iceberg.default` database, initially partitioned by `month(ts)`.
2.  **Spec Evolution + Ingestion**: After evolving the spec (e.g., adding `bucket(16, id)`), new data is written under the updated partition spec.
3.  **Partition Discovery**: `show-partitions` reflects partitions corresponding to the data written before and after the spec evolution.
4.  **Query Verification**: Queries return all ingested data. Filters on partition columns can enable pruning and improve performance.

## 5. Cleanup

Run the following command to stop and remove all Docker containers started for this scenario.

```bash
just down
```
