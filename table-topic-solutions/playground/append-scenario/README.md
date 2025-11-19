# Scenario: Append-Only Ingestion with Avro & Schema Evolution

Welcome! This lab demonstrates how to stream Avro events into an Apache Iceberg table and watch as Table Topic automatically handles schema evolution. 

By the end, you will have:
- An Iceberg table created entirely from Avro messages.
- Proof that the table schema evolves automatically when new fields are added.
- Sample queries that highlight how Avro types map to Iceberg.

## Getting Started

First, ensure the lab environment is running. If you haven't already, run `just up` once from the playground root to bring Kafka, Schema Registry, and Trino online. All commands in this guide should be run from the playground root directory.

## Step-by-Step Guide

### Step 1: Create the Table Topic

Let's start by creating the `orders` topic with Table Topic settings. This will serve as the sink for our data.

```bash
just -f append-scenario/justfile create-topic
```

Kafka will print either “Created topic orders” or “Topic already exists,” both of which are fine. No Iceberg artifacts are created yet.

### Step 2: Produce V1 Data (Baseline Schema)

Now, we'll register the initial `Order.avsc` schema and push some baseline records. This action will trigger Iceberg to automatically create the table.

```bash
just -f append-scenario/justfile send-auto
```

The `kafka-avro-console-producer` will report successful writes. You can now find an `iceberg.default.orders` table containing only the V1 columns.

### Step 3: Inspect the V1 Table

Let's confirm that every Avro type (primitive, logical, and complex) was mapped to the correct Iceberg column type.

```bash
just -f append-scenario/justfile show-ddl
just -f append-scenario/justfile show-files
```

The `SHOW CREATE TABLE` output will list scalar columns plus nested `ROW`, `ARRAY`, and `MAP` types. The `show-files` command will reveal at least one Iceberg data file.

You can use this helper query to connect fields to values:
```sql
SELECT order_id,
       order_status,
       shipping_address.city AS ship_city,
       product_tags,
       custom_attributes['k1'] AS attr_sample
FROM iceberg.default.orders
ORDER BY order_id
LIMIT 5;
```

### Step 4: Produce V2 Data (Schema Evolution)

Next, we'll send events encoded with `OrderV2.avsc`. This new schema version introduces nullable columns, new collections, and nested structs, putting schema evolution to the test.

```bash
just -f append-scenario/justfile send-auto-v2
```

The console producer should succeed, and Schema Registry will now have a new version for the `orders-value` subject.

### Step 5: Verify the Evolved Table

This step shows that Iceberg automatically picked up every new field and that old records remain perfectly readable.

```bash
just -f append-scenario/justfile show-ddl
just -f append-scenario/justfile show-history
```

The DDL output now includes nullable columns like `total_amount`, `tax_amount`, `billing_address`, and `payment_status`. The table history will show two commits (one for the V1 load, one for V2).

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
Notice that V1 rows return `NULL` for V2-only columns, while V2 rows contain real values.

### Step 6: Explore and Document (Optional)

If you want to capture evidence of the evolution for demos or documentation, these commands are helpful.

```bash
just -f append-scenario/justfile query
just -f append-scenario/justfile show-manifests
```

`query` runs a default `SELECT * LIMIT 20`. `show-manifests` proves Iceberg is tracking data files from both schema versions. For a textual diff, you can save the DDL output before and after Step 4 and run `diff -u`.

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