# Scenario: Dynamic Protobuf Ingestion with `by_latest_schema`

This scenario demonstrates dynamic Protobuf ingestion using the `by_latest_schema` strategy. It illustrates how Table Topic fetches the latest schema from the Schema Registry on demand, enabling automatic Iceberg table evolution upon `.proto` file updates.

This "late binding" approach is ideal for environments where producers can't or shouldn't be aware of schema IDs.

## Getting Started

Before we begin, make sure the environment is up by running `just up` from the playground root. All subsequent commands should also be run from there. Our scripts assume Schema Registry is available at `http://schema-registry:8081`.

## Step-by-Step Guide

### Step 1: Register the Protobuf Schemas

Publish the Protobuf schemas (`common.proto`, `user.proto`, and `product.proto`) to the Schema Registry. This enables Table Topic to resolve them by subject name.

```bash
just -f protobuf-latest-scenario/justfile register
```

Maven will report successful registration for `common-value`, `user-value`, and `product-value`. Schema Registry now tracks the cross-file references between them.

### Step 2: Inspect Registered Subjects (Optional)

You can verify that the subjects and versions are in the registry before producing data. This is also a great sanity check for demos.

```bash
just -f protobuf-latest-scenario/justfile show-schemas
```

You'll see a list of subjects and a pretty-printed JSON representation of the schemas, confirming that `examples.clients.proto.ProductData` and `UserData` are available.

### Step 3: Create the Table Topics

Configure the Kafka topics (`product`, `user`) as Iceberg tables. The setting `automq.table.topic.convert.value.type=by_latest_schema` enables dynamic schema fetching.

```bash
just -f protobuf-latest-scenario/justfile create-product-topic
just -f protobuf-latest-scenario/justfile create-user-topic
```

Kafka will acknowledge the topic creations (or note that they already exist). At this stage, no Iceberg tables have been created.

#### Key Configuration Parameters

When creating the topic, several configurations control the Table Topic behavior:

*   `automq.table.topic.enable=true`: Activates the Table Topic feature for this specific topic.
*   `automq.table.topic.convert.value.type=by_latest_schema`: Instructs the broker to fetch the *latest* registered schema from the Schema Registry for decoding, rather than relying on an embedded Schema ID.
*   `automq.table.topic.convert.value.by_latest_schema.message.full.name=...`: Specifies the fully qualified Protobuf message name (e.g., `examples.clients.proto.ProductData`) to look up in the registry.
*   `automq.table.topic.transform.value.type=flatten`: Flattens the message structure into top-level Iceberg columns.

### Step 4: Produce Raw Protobuf Messages

Send raw (unframed) Protobuf messages to Kafka. This triggers the server to fetch the latest schema from the registry for decoding.

```bash
just -f protobuf-latest-scenario/justfile send-product-raw
just -f protobuf-latest-scenario/justfile send-user-raw
```

The Python producer will log successful sends. After this, Iceberg will materialize the `iceberg.default.product` and `iceberg.default.user` tables, complete with dozens of columns each.

### Step 5: Inspect the Generated Tables

Verify that all Protobuf constructs (including `repeated`, `map`, `enum`, nested messages, and timestamps) are correctly mapped to the corresponding Iceberg types.

```bash
just -f protobuf-latest-scenario/justfile show-ddl product
just -f protobuf-latest-scenario/justfile show-ddl user
```

The `SHOW CREATE TABLE` output will reveal `array`, `map`, and `row` columns. You'll also see special `_choice` columns for `oneof` fields.

To inspect the data, open a Trino SQL shell:

```bash
docker compose exec trino trino
```

Then run these helper queries:

```sql
-- Product data
SELECT product_id,
       attributes['color'] AS color,
       availability_windows['WEEKDAY'].start_timestamp AS weekday_start,
       warehouse_address.city AS warehouse_city
FROM iceberg.default.product
LIMIT 5;

-- User data
SELECT user_id,
       preferences['theme'] AS theme,
       contacts_by_channel['EMAIL'].email AS email_contact,
       trusted_contacts[1].email AS backup_contact
FROM iceberg.default."user"
LIMIT 5;
```

### Step 6: Explore Iceberg Metadata (Optional)

To show your audience that the ingestion process really wrote data files to the table, run the following command.

```bash
just -f protobuf-latest-scenario/justfile show-files product
```

The output will list the Parquet files and their corresponding record counts for the `product` table. You can do the same for the `user` table if you'd like.

### Step 7: Optional: Schema Evolution Drill

To observe dynamic handling of schema changes, perform the following schema evolution drill:

1.  Edit `protobuf-latest-scenario/scripts/schema/product.proto` and add a new field (e.g., `optional string warranty_code = 35;`).
2.  Re-register the schema: `just -f protobuf-latest-scenario/justfile register`.
3.  Produce another message: `just -f protobuf-latest-scenario/justfile send-product-raw`.
4.  Check the DDL again. You'll see the new nullable Iceberg column appear automatically!

### Step 8: Cleanup

When you're done, free up the system resources.

```bash
just down
```

The Docker stack will stop. Rerun `just up` the next time you need the lab.

## Protobuf to Iceberg Type Mapping

| Protobuf Type | Iceberg Type | Notes |
| :--- | :--- | :--- |
| `int32`, `sint32`, `sfixed32` | `int` | Stored as signed integer |
| `uint32`, `fixed32` | `int` | Iceberg does not natively support unsigned types;|
| `int64`, `sint64`, `sfixed64` | `long` | Stored as signed long |
| `uint64`, `fixed64` | `long` | Iceberg does not natively support unsigned types; |
| `float` | `float` | — |
| `double` | `double` | — |
| `bool` | `bool` | — |
| `string` | `string` | — |
| `bytes` | `binary` | — |
| `enum` | `string` | The symbol string value is stored. |
| `repeated` | `list` |  |
| `map` | `map` |  |
| `message` | `struct` | Proto2 `group` fields are not supported. |
| `google.protobuf.Timestamp` | `timestamp-micros` | - |


**Limitations**

* **Proto2 `group` fields** and **recursive** message definitions are **not supported**.
* **Unsigned integers** (`uint32`, `fixed32`, `uint64`, `fixed64`) are stored as signed types (`int` or `long`). Bit patterns are preserved, ensuring no data loss when interpreted as unsigned.

---

## Key Takeaways

* You ingested Protobuf data without embedding schema IDs—**Table Topic** fetched the schemas on demand.
* **Iceberg tables** were created automatically, correctly reflecting every `repeated`, `map`, `enum`, and **nested field** from your `.proto` files.
* Re-registering a new schema version **instantly and automatically** updates the table structure for future writes, **all without restarting any services**.
