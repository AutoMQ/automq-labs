# Scenario: Partitioned Ingestion

## 1. Scenario Objective

This scenario demonstrates how to ingest data into a **partitioned** Iceberg table. Partitioning is a key optimization strategy that organizes data in the storage layer based on the values of one or more columns, which can significantly improve query performance by allowing query engines to prune (skip) irrelevant data files.

## 2. Core Configuration

This scenario relies on the following key Table Topic configurations to create a partitioned table:

- `automq.table.topic.convert.value.type=by_schema_id`: Decodes the Avro message using its schema from Schema Registry.
- `automq.table.topic.transform.value.type=flatten`: Flatten the Kafka value payload into table columns (nested structures → columns).
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

### Step 3: Produce Data

This command produces Avro records containing a timestamp field and sends them to the `order-with-ts` topic.

```bash
just -f partition-scenario/justfile send-auto
```

### Step 4: Show Partitions and Query Data

Check the partitions created in the Iceberg table and then query the data.

```bash
# Show the partitions that have been created
just -f partition-scenario/justfile show-partitions

# Query the data from the table
just -f partition-scenario/justfile query
```

## 4. Expected Outcome

1.  **Partitioned Table Creation**: An Iceberg table named `order-with-ts` is created in the `iceberg.default` database, partitioned by `month(ts)`.
2.  **Data Ingestion**: Ingested data is physically organized into different directories in storage based on the month of the `ts` field.
3.  **Partition Discovery**: Running `show-partitions` displays the distinct partitions that have been created in the table, confirming that the partitioning logic is working.
4.  **Query Verification**: Queries against the table return the ingested data. Queries that include a filter on the `ts` column (e.g., `WHERE ts >= ...`) will benefit from partition pruning, leading to faster execution on large datasets.

## 5. Cleanup

Run the following command to stop and remove all Docker containers started for this scenario.

```bash
just down
```
