# Scenario: Protobuf Ingestion with by_latest_schema

## 1. Goal (Why You Are Here)
Ingest raw Protobuf messages **without** schema IDs, let Table Topic fetch the latest schema from Schema Registry at read time, and watch Iceberg tables update automatically whenever you evolve the `.proto` files.

## 2. Before You Start
- Make sure `just up` is already running (you mentioned it is). All commands below run from the Playground root.
- The helper scripts assume Schema Registry is reachable at `http://schema-registry:8081` and Trino is ready for queries.

## 3. Lab Walkthrough
Each step provides the **Why**, the **Command**, and what you should **Expect**. Follow the order for a clean story.

### Step 1 – Register the Protobuf Schemas
- **Why**: Publish `common.proto`, `user.proto`, and `product.proto` so Table Topic can decode by subject name.
- **Command**:
  ```bash
  just -f protobuf-latest-scenario/justfile register
  ```
- **Expect**: Maven reports successful registration for `common-value`, `user-value`, and `product-value`. Schema Registry now tracks cross-file references.

### Step 2 – Inspect Registered Subjects (optional but recommended)
- **Why**: Verify subjects/versions before producing data; great for demos.
- **Command**:
  ```bash
  just -f protobuf-latest-scenario/justfile show-schemas
  ```
- **Expect**: List of subjects plus pretty-printed schema JSON, confirming `examples.clients.proto.ProductData` and `UserData` are available.

### Step 3 – Create Table Topics
- **Why**: Wire Kafka topics (`product`, `user`) to Iceberg tables with `automq.table.topic.convert.value.type=by_latest_schema`.
- **Commands**:
  ```bash
  just -f protobuf-latest-scenario/justfile create-product-topic
  just -f protobuf-latest-scenario/justfile create-user-topic
  ```
- **Expect**: Kafka acknowledges topic creation (or notes that they already exist). No Iceberg tables yet.

### Step 4 – Produce Raw Protobuf Messages
- **Why**: Send unframed Protobuf bytes so the server must fetch the latest schema to decode.
- **Commands**:
  ```bash
  just -f protobuf-latest-scenario/justfile send-product-raw
  just -f protobuf-latest-scenario/justfile send-user-raw
  ```
- **Expect**: The Python producer logs successful sends. Iceberg now materializes `iceberg.default.product` and `iceberg.default.user` with dozens of columns.

### Step 5 – Inspect the Generated Tables
- **Why**: Prove that every Protobuf construct (repeated, map, enum, nested message, timestamp) became the correct Iceberg type.
- **Commands**:
  ```bash
  just -f protobuf-latest-scenario/justfile show-ddl product
  just -f protobuf-latest-scenario/justfile show-ddl user
  ```
- **Expect**: `SHOW CREATE TABLE` reveals `array`, `map`, and `row` columns, plus `_choice` columns for `oneof`. Run these helper queries to see data:
  ```sql
  -- Product focus
  SELECT product_id,
         attributes['color'] AS color,
         availability_windows['WEEKDAY'].start_timestamp AS weekday_start,
         warehouse_address.city AS warehouse_city
  FROM iceberg.default.product
  LIMIT 5;

  -- User focus
  SELECT user_id,
         preferences['theme'] AS theme,
         contacts_by_channel['EMAIL'].email AS email_contact,
         trusted_contacts[1].email AS backup_contact
  FROM iceberg.default."user"
  LIMIT 5;
  ```

### Step 6 – Explore Iceberg Metadata (optional)
- **Why**: Show your audience that the ingestion really wrote data files.
- **Command**:
  ```bash
  just -f protobuf-latest-scenario/justfile show-files product
  ```
- **Expect**: Output lists Parquet files with record counts for the `product` table. Repeat with `user` if desired.

### Step 7 – (Optional) Run a Schema Evolution Drill
- **Why**: Demonstrate that `by_latest_schema` always pulls the newest schema.
- **Workflow**:
  1. Edit `schema/product.proto` to add fields (e.g., `optional string warranty_code = 35;`).
  2. Re-run `just -f protobuf-latest-scenario/justfile register`.
  3. Produce another product message.
  4. Compare DDLs by saving `SHOW CREATE TABLE` output before and after, then `diff -u`. New nullable Iceberg columns should appear automatically.

### Step 8 – Cleanup When Done
- **Why**: Free containers.
- **Command**:
  ```bash
  just down
  ```
- **Expect**: Docker stack stops; re-run `just up` next time.

## 4. Reference: Protobuf → Iceberg Mapping

| Protobuf concept | Iceberg type | Notes |
| --- | --- | --- |
| `repeated T` | `array<T>` | Repeated messages become `array(row(...))` |
| `map<K,V>` | `map(varchar, …)` | Keys are strings; message values become `row(...)` |
| `int32`, `sint32`, `sfixed32` | `integer` | Signed storage |
| `uint32`, `fixed32` | `integer` | Iceberg stores as signed; large values may wrap |
| `int64`, `sint64`, `sfixed64` | `bigint` | Signed storage |
| `uint64`, `fixed64` | `bigint` | Stored as signed; beware overflow semantics |
| `bool` | `boolean` | — |
| `float` | `real` | — |
| `double` | `double` | — |
| `string` | `varchar` | — |
| `bytes` | `varbinary` | — |
| `enum` | `varchar` | Symbol string is stored |
| `message` | `row(...)` | Proto2 `group` fields are not supported |
| `google.protobuf.Timestamp` | `timestamp(6)` | Converted to microseconds |

**Limitations**
- Proto2 `group` and recursive message definitions are unsupported.
- Unsigned integers have no dedicated Iceberg type; very large values may exceed signed ranges.

## 5. Wrap-Up
- You ingested Protobuf data without embedding schema IDs—Table Topic fetched schemas on demand.
- Iceberg tables materialized automatically and reflect every repeated, map, enum, and nested field.
- Re-registering a schema instantly changes future writes, letting you demonstrate evolution without restarting services.
