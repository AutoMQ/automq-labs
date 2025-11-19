# Scenario: Protobuf Ingestion with Latest Schema

## 1. Scenario Objective

This scenario demonstrates how to ingest raw **Protobuf** messages into an Iceberg table. Unlike Avro, these messages are not framed with a schema ID. Instead, the server decodes the raw Protobuf bytes by fetching the **latest registered schema** for a specific subject from the Schema Registry.

## 2. Core Configuration

This scenario relies on the following key Table Topic configurations for server-side Protobuf decoding:
- `automq.table.topic.convert.value.type=by_latest_schema`: Instructs the server to decode the message payload by fetching the latest schema version associated with a given subject.
- `automq.table.topic.convert.value.subject`: Specifies the subject name in Schema Registry to look up (e.g., `product-value`).
- `automq.table.topic.convert.value.message.full.name`: Specifies the fully qualified name of the Protobuf message type to use for decoding.
- `automq.table.topic.transform.value.type=flatten`: Maps the fields inside the Kafka record's value into top-level table columns (the key is not used for column mapping).

## 3. Schema Design

Both `.proto` files intentionally exercise nearly every scalar, complex, and collection type that Protobuf offers so you can see how they show up in Iceberg.

### `product.proto`

- **Scalars**: `double`, `float`, `bool`, `int32`, `sint32`, `uint32`, `int64`, `sint64`, `uint64`, `fixed32`, `sfixed32`, `fixed64`, `sfixed64`
- **Binary & Logical**: `bytes product_image`, `google.protobuf.Timestamp created_at/updated_at`
- **Enums & Nested Messages**: `ProductStatus`, nested `ProductCategory`, shared `Address`, `ContactInfo`, `TimeRange`
- **Collections**: repeated scalars (`tags`, `related_product_ids`), repeated messages (`sub_categories`, `shipping_origins`, `vendor_contacts`)
- **Maps**:
  - `map<string, string> attributes`
  - `map<string, int64> price_history`
  - `map<string, TimeRange> availability_windows`
- **Advanced Constructs**: optional fields (`manufacturer`), `oneof seller_info`

### `user.proto`

- **Scalars**: Mirrors the full numeric range plus `double/float/bool`
- **Binary & Logical**: `bytes profile_picture`, `google.protobuf.Timestamp registered_at/last_login_at`
- **Enums & Nested**: `UserRole`, shared `Address`, repeated `shipping_addresses`
- **Maps**:
  - `map<string, string> preferences`
  - `map<string, ContactInfo> contacts_by_channel`
  - `map<string, int64> login_counts`
- **Advanced Constructs**: optional `referral_code`, `oneof contact_method`, repeated shared message `trusted_contacts`

When these schemas are flattened into Iceberg tables, every scalar becomes a column, nested messages become structured columns (`ROW(...)` in Trino), and maps/repeated fields turn into Iceberg `map`/`array` types. The data producers in `kafka_protobuf_producer.py` intentionally populate every field so you can observe the serialization results.

### Observation Guide

| Feature | Product fields | User fields | How to verify |
| --- | --- | --- | --- |
| Numeric variety | `stock_quantity`, `reserved_quantity`, `total_revenue_cents`, `sku_hash`, `warehouse_zone`, `barcode`, `internal_id` | `total_orders`, `loyalty_points`, `profile_views`, `user_hash`, `timezone_offset`, `phone_number`, `internal_user_id` | `SHOW CREATE TABLE iceberg.default.product` and `DESCRIBE` → note `integer`, `bigint`, `real`, `varbinary` |
| Logical timestamps | `created_at`, `updated_at` | `registered_at`, `last_login_at` | Query the table and compare timezone precision |
| Optional & oneof | `manufacturer`, `seller_name`/`seller_id` | `referral_code`, `contact_email`/`contact_phone` | Observe nullable columns + `_choice` columns in Iceberg |
| Maps | `attributes`, `price_history`, `availability_windows` | `preferences`, `contacts_by_channel`, `login_counts` | Query map keys using `map['key']` expressions |
| Shared nested types | `warehouse_address`, `supplier_contact`, `vendor_contacts` | `address`, `shipping_addresses`, `trusted_contacts` | `SELECT warehouse_address.city` or `trusted_contacts[1].email` |

## 4. Steps to Run

Follow these steps to run the demonstration.

### Step 1: Start Services

Start the base services required for the scenario.

```bash
just up
```

### Step 2: Register Protobuf Schemas

Compile and register the `.proto` schema files with Schema Registry.

```bash
just -f protobuf-latest-scenario/justfile register
```

### Step 3: Inspect Registered Schemas

Validate the subjects/versions and inspect the exact schema text.

```bash
just -f protobuf-latest-scenario/justfile show-schemas
```

### Step 4: Create Table Topics

Create two Table Topics, `product` and `user`, configured to use the latest schema for decoding.

```bash
just -f protobuf-latest-scenario/justfile create-product-topic
just -f protobuf-latest-scenario/justfile create-user-topic
```

### Step 5: Produce Raw Protobuf Data

Produce raw, unframed Protobuf messages to their respective topics.

```bash
just -f protobuf-latest-scenario/justfile send-product-raw
just -f protobuf-latest-scenario/justfile send-user-raw
```

### Step 6: View Table DDL

Inspect the Iceberg table definitions created for each topic.

```bash
just -f protobuf-latest-scenario/justfile show-ddl product
just -f protobuf-latest-scenario/justfile show-ddl user
```

### Step 7: View Table Info

Inspect metadata tables to see snapshots, manifests, and physical files.

```bash
# For 'product'
just -f protobuf-latest-scenario/justfile show-snapshots product
just -f protobuf-latest-scenario/justfile show-history product
just -f protobuf-latest-scenario/justfile show-files product
just -f protobuf-latest-scenario/justfile show-manifests product

# For 'user'
just -f protobuf-latest-scenario/justfile show-snapshots user
just -f protobuf-latest-scenario/justfile show-history user
just -f protobuf-latest-scenario/justfile show-files user
just -f protobuf-latest-scenario/justfile show-manifests user
```

### Step 8: Query Iceberg Data

Query the tables via Trino to see the structured, decoded data.

```bash
just -f protobuf-latest-scenario/justfile query-product
just -f protobuf-latest-scenario/justfile query-user
```

Sample queries tying back to the observation guide:

```sql
-- Map lookups and nested structs
SELECT product_id,
       attributes['color'] AS color,
       price_history['2025-01'] AS price_jan,
       availability_windows['WEEKDAY'].start_timestamp AS weekday_start,
       warehouse_address.city AS warehouse_city
FROM iceberg.default.product
LIMIT 5;

SELECT user_id,
       preferences['theme'] AS theme,
       contacts_by_channel['EMAIL'].email AS email_contact,
       trusted_contacts[1].email AS backup_contact,
       favorite_product_ids
FROM iceberg.default."user"
LIMIT 5;
```

### Step 9 (Optional): Run a Schema Evolution Drill

The `by_latest_schema` converter immediately reflects new schema versions. To see how Iceberg reacts:

1. Append a new field (e.g., an optional string plus a map) near the bottom of `schema/product.proto`:

   ```proto
   // --- V2 demo fields ---
   optional string warranty_code = 35;
   map<string, string> audit_tags = 36;
   ```

2. Re-run the register command to push Version 2:

   ```bash
   just -f protobuf-latest-scenario/justfile register
   just -f protobuf-latest-scenario/justfile show-schemas
   ```

3. Produce more product records and inspect the table:

   ```bash
   just -f protobuf-latest-scenario/justfile send-product-raw
   just -f protobuf-latest-scenario/justfile show-ddl product
   just -f protobuf-latest-scenario/justfile query-product
   ```

You should observe two new nullable columns (`warranty_code`, `audit_tags`) in `iceberg.default.product`. Older rows display `NULL`, while new rows show the populated values—mirroring the evolution behavior highlighted in the Avro scenario.

Capture the `SHOW CREATE TABLE` output before/after the schema tweak if you want a textual diff:

```bash
just -f protobuf-latest-scenario/justfile show-ddl product > /tmp/product_v1.sql   # before editing .proto
just -f protobuf-latest-scenario/justfile show-ddl product > /tmp/product_v2.sql   # after re-registering
diff -u /tmp/product_v1.sql /tmp/product_v2.sql
```

## 5. Expected Outcome

1.  **Schemas Registered**: The `product-value` and `user-value` subjects are successfully registered in Schema Registry.
2.  **Iceberg Table Creation**: Two Iceberg tables, `product` and `user`, are created in the `iceberg.default` database with dozens of columns spanning every Protobuf type category.
3.  **Server-Side Decoding**: The Table Topic service successfully decodes the raw Protobuf byte streams by fetching the latest schemas from Schema Registry and maps the Kafka record value fields into the corresponding tables.
4.  **Schema Evolution Visibility**: Re-registering an evolved schema immediately adds nullable Iceberg columns that reflect the new Protobuf fields while preserving existing data.
5.  **Query Verification**: Queries against the `product` and `user` tables in Trino return structured, readable data covering repeated fields, maps, logical types, and nested records.

## 6. Cleanup

Stop and remove all Docker containers started for this scenario.

```bash
just down
```
