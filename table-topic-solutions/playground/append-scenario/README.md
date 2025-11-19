# Scenario: Append-Only Ingestion with Avro & Schema Evolution

This scenario demonstrates streaming Avro events into an Apache Iceberg table, showcasing how Table Topic automatically manages schema evolution.

By the end, you will have:
- An Iceberg table created entirely from Avro messages.
- Proof that the table schema evolves automatically when new fields are added.
- Sample queries that highlight how Avro types map to Iceberg.

## Getting Started

First, ensure the lab environment is running. If you haven't already, run `just up` once from the playground root to bring Kafka, Schema Registry, and Trino online. All commands in this guide should be run from the playground root directory.

## Step-by-Step Guide

### Step 1: Create the Table Topic

Create the `orders` topic configured with Table Topic settings. This topic will serve as the data sink.

```bash
just -f append-scenario/justfile create-topic
```

The command output will confirm that the topic `orders` has been created (or already exists). No Iceberg artifacts are created at this stage.

### Step 2: Produce V1 Data (Baseline Schema)

Register the initial `Order.avsc` schema and produce baseline records. This operation triggers the automatic creation of the Iceberg table.

```bash
just -f append-scenario/justfile send-auto
```

The producer will report successful writes. You can now find an `iceberg.default.orders` table containing only the V1 columns.

### Step 3: Inspect the V1 Table

Verify that all Avro types (primitive, logical, and complex) are correctly mapped to their corresponding Iceberg column types.

```bash
just -f append-scenario/justfile show-ddl
just -f append-scenario/justfile show-files
```

The `SHOW CREATE TABLE` output will display the schema. Look for:
*   **Primitives**: `string` -> `varchar`, `long` -> `bigint`.
*   **Complex Types**: `record` -> `ROW`, `array` -> `ARRAY`, `map` -> `MAP`.

The `show-files` command will list the underlying Parquet files created by the ingestion process.

### Step 4: Produce V2 Data (Schema Evolution)

Send events encoded with `OrderV2.avsc`. This schema version introduces nullable columns, new collections, and nested structs to demonstrate schema evolution.

```bash
just -f append-scenario/justfile send-auto-v2
```

The producer will send new data, and Schema Registry will register a new version for the `orders-value` subject.

### Step 5: Verify the Evolved Table

Verify that Iceberg has automatically detected the new fields and that existing records remain readable.

```bash
just -f append-scenario/justfile show-ddl
just -f append-scenario/justfile show-history
```

The DDL output will now include the new nullable columns (e.g., `total_amount`, `payment_status`). The table history will show a new snapshot corresponding to the V2 ingestion.

To verify the data evolution, open a Trino SQL shell:

```bash
docker compose exec trino trino
```

Then run this comparison query:

```sql
SELECT order_id,
       price,
       total_amount,
       tax_amount,
       billing_address.country AS billing_country,
       payment_status
FROM iceberg.default.orders
ORDER BY order_id DESC
LIMIT 10;
```

**Understanding the Output:**

| Data Version | Old Columns (e.g., `price`) | New Columns (e.g., `payment_status`) |
| :--- | :--- | :--- |
| **V2 Rows** | Value Present | **Value Present** |
| **V1 Rows** | Value Present | **NULL** |

Since V1 records were written before the new columns existed, Iceberg returns `NULL` for those fields, ensuring backward compatibility.

### Step 6: Explore and Document (Optional)

To capture evidence of the evolution for demonstration or documentation purposes, use the following commands.

```bash
just -f append-scenario/justfile query
just -f append-scenario/justfile show-manifests
```

`query` runs a default `SELECT * LIMIT 20`. `show-manifests` lists the metadata files, proving that Iceberg is tracking data files from both schema versions.

### Step 2: Produce V1 Data (Baseline Schema)

Register the initial `Order.avsc` schema and produce baseline records. This operation triggers the automatic creation of the Iceberg table.

```bash
just -f append-scenario/justfile send-auto
```

The producer will report successful writes. You can now find an `iceberg.default.orders` table containing only the V1 columns.

### Step 3: Inspect the V1 Table

Verify that all Avro types (primitive, logical, and complex) are correctly mapped to their corresponding Iceberg column types.

```bash
just -f append-scenario/justfile show-ddl
just -f append-scenario/justfile show-files
```

The `SHOW CREATE TABLE` output will display the schema. Look for:
*   **Primitives**: `string` -> `varchar`, `long` -> `bigint`.
*   **Complex Types**: `record` -> `ROW`, `array` -> `ARRAY`, `map` -> `MAP`.

The `show-files` command will list the underlying Parquet files created by the ingestion process.

### Step 4: Produce V2 Data (Schema Evolution)

Send events encoded with `OrderV2.avsc`. This schema version introduces nullable columns, new collections, and nested structs to demonstrate schema evolution.

```bash
just -f append-scenario/justfile send-auto-v2
```

The producer will send new data, and Schema Registry will register a new version for the `orders-value` subject.

### Step 5: Verify the Evolved Table

Verify that Iceberg has automatically detected the new fields and that existing records remain readable.

```bash
just -f append-scenario/justfile show-ddl
just -f append-scenario/justfile show-history
```

The DDL output will now include the new nullable columns (e.g., `total_amount`, `payment_status`). The table history will show a new snapshot corresponding to the V2 ingestion.

This comparison query makes the evolution clear:
```sql
SELECT order_id,
       price,
       total_amount,
       tax_amount,
       billing_address.country AS billing_country,
       payment_status
FROM iceberg.default.orders
ORDER BY order_id DESC
LIMIT 10;
```

**Understanding the Output:**

| Data Version | Old Columns (e.g., `price`) | New Columns (e.g., `payment_status`) |
| :--- | :--- | :--- |
| **V2 Rows** | Value Present | **Value Present** |
| **V1 Rows** | Value Present | **NULL** |

Since V1 records were written before the new columns existed, Iceberg returns `NULL` for those fields, ensuring backward compatibility.

### Step 6: Explore and Document (Optional)

To capture evidence of the evolution for demonstration or documentation purposes, use the following commands.

```bash
just -f append-scenario/justfile query
just -f append-scenario/justfile show-manifests
```

`query` runs a default `SELECT * LIMIT 20`. `show-manifests` lists the metadata files, proving that Iceberg is tracking data files from both schema versions.

### Step 7: Cleanup

When you're finished, run this command to free up system resources.

```bash
just down
```

The Docker containers will stop. You can rerun `just up` the next time you want to use the lab.

## Avro to Iceberg Type Mapping

| Avro Type / Logical Type | Iceberg Type | Notes |
| :--- | :--- | :--- |
| `boolean` | `boolean` | — |
| `int` | `int` | — |
| `long` | `long` | — |
| `float` | `float` | — |
| `double` | `double` | — |
| `bytes` | `binary` | — |
| `string` | `string` | — |
| `record` | `struct` | — |
| `array` | `list` | — |
| `list<struct{key, value}>` | `map` | **Non-string keys are supported** using Avro logicalType=map array record structure. |
| `fixed` | `fixed` | — |
| `decimal` | `decimal` | — |
| `uuid` | `uuid` | — |
| `date` | `date` | — |
| `time` | `time` | `time-millis` / `time-micros` logical types are mapped to Iceberg `TIME` (`LocalTime`). **Precision is unified to microseconds.** |
| `timestamp` | `timestamp` | `timestamp-micros` / `timestamp-millis` (including `adjust-to-utc` logical types) are mapped to Iceberg `TIMESTAMP`. |

> **Note**: Optional fields must be expressed as a union, like `["null", type]` or `[type, "null"]`. **Unions containing multiple non-null types are not supported.**

---

## Key Takeaways

* You created an Iceberg table purely by sending Avro payloads—**no manual DDL required**.
* **Schema evolution** was handled automatically just by producing records with a new Avro schema.
* The verification queries show how primitive, logical, and complex Avro types appear in Trino, making it easy to see the feature in action.