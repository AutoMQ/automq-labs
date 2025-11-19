# Scenario: Append-Only Ingestion (Avro by_schema_id)

## 1. Goal (Why You Are Here)
Stream Avro events into an Iceberg table, then evolve the schema to prove that Table Topic automatically keeps the table in sync. By the end you will have: (a) a table created entirely from Avro messages, (b) proof that new nullable columns show up after evolution, and (c) sample queries that highlight how each Avro type maps to Iceberg.

## 2. Before You Start
- Run `just up` once per session (already done) so Kafka, Schema Registry, Iceberg, and Trino are online.
- All commands below run from the Playground root. They are prefixed with an explanation so you always know why you are typing them.

## 3. Lab Walkthrough
Each step follows the same rhythm: **Why** you should run it, the **Command**, what you **Expect**, and any special **Notes**.

### Step 1 – Create the Table Topic
- **Why**: Establish the `orders` topic with Table Topic settings so downstream steps have a sink.
- **Command**:
  ```bash
  just -f append-scenario/justfile create-topic
  ```
- **Expect**: Kafka prints either “Created topic orders” or “Topic already exists”; both are fine. No Iceberg artifacts yet.

### Step 2 – Produce V1 Data (baseline schema)
- **Why**: Register `Order.avsc`, push baseline rows, and let Iceberg auto-create the table.
- **Command**:
  ```bash
  just -f append-scenario/justfile send-auto
  ```
- **Expect**: `kafka-avro-console-producer` reports successful writes. Iceberg now contains `iceberg.default.orders` with only V1 columns.

### Step 3 – Inspect the Table After V1
- **Why**: Confirm that every Avro type (primitive, logical, complex) became the expected Iceberg column.
- **Commands**:
  ```bash
  just -f append-scenario/justfile show-ddl
  just -f append-scenario/justfile show-files
  ```
- **Expect**: `SHOW CREATE TABLE` lists scalar columns plus nested `ROW`, `ARRAY`, and `MAP` types. `show-files` reveals at least one Iceberg data file. Use this helper query to tie fields to values:
  ```sql
  SELECT order_id,
         order_status,
         shipping_address.city AS ship_city,
         product_tags,
         custom_attributes['loyalty-tier'] AS loyalty_tier
  FROM iceberg.default.orders
  ORDER BY order_id
  LIMIT 5;
  ```

### Step 4 – Produce V2 Data (schema evolution)
- **Why**: Send events encoded with `OrderV2.avsc` to introduce nullable columns, new collections, and nested structs.
- **Command**:
  ```bash
  just -f append-scenario/justfile send-auto-v2
  ```
- **Expect**: Console producer succeeds; Schema Registry now holds a new version for the `orders` value subject.

### Step 5 – Verify the Evolved Table
- **Why**: Show that Iceberg picked up every new field automatically and that old records remain readable.
- **Commands**:
  ```bash
  just -f append-scenario/justfile show-ddl
  just -f append-scenario/justfile show-history
  ```
- **Expect**: DDL output now includes nullable columns such as `total_amount`, `tax_amount`, `billing_address`, and `payment_status`. History shows two commits (V1 load then V2 load). Use this comparison query:
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
  V1 rows return `NULL` for V2-only columns; V2 rows include real values.

### Step 6 – Explore and Document
- **Why**: Capture evidence of the evolution for demos or docs.
- **Commands (optional)**:
  ```bash
  just -f append-scenario/justfile query
  just -f append-scenario/justfile show-manifests
  ```
- **Expect**: `query` runs a default `SELECT * LIMIT 20`. `show-manifests` proves Iceberg tracks files added during both schema versions. If you need a textual diff, save the DDL before and after Step 4 and run `diff -u`.

### Step 7 – Cleanup (when finished)
- **Why**: Free resources.
- **Command**:
  ```bash
  just down
  ```
- **Expect**: Docker containers stop; rerun `just up` next time you need the lab.

## 4. Reference: Avro → Iceberg Mapping

| Avro type / logical type | Iceberg type | Notes |
| --- | --- | --- |
| `boolean` | `boolean` | — |
| `int` | `integer` | Includes `date`, `time-millis` logicals |
| `long` | `bigint` | Includes `timestamp-millis/micros` logicals |
| `float` | `real` | — |
| `double` | `double` | — |
| `bytes` | `varbinary` | Used for `decimal`, `fixed` |
| `string` | `varchar` | `uuid` logical type maps to Iceberg `uuid` |
| `record` | `row(...)` | Nested struct; recursion not supported |
| `array` | `array(...)` | — |
| `map` | `map(varchar, …)` | Keys are strings |
| `fixed` | `varbinary` / `fixed` | Size preserved |
| `decimal(p,s)` | `decimal(p,s)` | Requires logical annotation |
| `date` | `date` | — |
| `time-micros` | `time(6)` | — |
| `timestamp` | `timestamp` | Millis/micros supported |

> Optional fields must be expressed as `["null", type]` or `[type, "null"]`.

## 5. Wrap-Up
- You created an Iceberg table purely by sending Avro payloads—no manual DDL.
- Schema evolution required only producing with a new Avro schema; Iceberg reflected the change automatically.
- The verification queries demonstrate how primitive, logical, and complex Avro types appear in Trino, making it easy to explain the feature to others.
