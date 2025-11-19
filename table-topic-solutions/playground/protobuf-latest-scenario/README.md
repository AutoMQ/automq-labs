# Scenario: Dynamic Protobuf Ingestion with `by_latest_schema`

This scenario demonstrates a powerful feature: ingesting raw Protobuf messages *without* embedded schema IDs. You'll see how Table Topic fetches the latest schema from Schema Registry on the fly, allowing Iceberg tables to evolve automatically whenever you update your `.proto` files.

This "late binding" approach is ideal for environments where producers can't or shouldn't be aware of schema IDs.

## Getting Started

Before we begin, make sure the environment is up by running `just up` from the playground root. All subsequent commands should also be run from there. Our scripts assume Schema Registry is available at `http://schema-registry:8081`.

## Step-by-Step Guide

### Step 1: Register the Protobuf Schemas

First, let's publish our Protobuf schemas (`common.proto`, `user.proto`, and `product.proto`) to the Schema Registry. This allows Table Topic to look them up by subject name later.

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

Now, let's wire the Kafka topics (`product`, `user`) to Iceberg tables. We'll configure them with `automq.table.topic.convert.value.type=by_latest_schema` to enable the dynamic schema fetching behavior.

```bash
just -f protobuf-latest-scenario/justfile create-product-topic
just -f protobuf-latest-scenario/justfile create-user-topic
```

Kafka will acknowledge the topic creations (or note that they already exist). At this stage, no Iceberg tables have been created.

### Step 4: Produce Raw Protobuf Messages

Here, we'll send unframed Protobuf bytes to Kafka. This forces the server to fetch the latest schema from the registry to decode the data.

```bash
just -f protobuf-latest-scenario/justfile send-product-raw
just -f protobuf-latest-scenario/justfile send-user-raw
```

The Python producer will log successful sends. After this, Iceberg will materialize the `iceberg.default.product` and `iceberg.default.user` tables, complete with dozens of columns each.

### Step 5: Inspect the Generated Tables

Let's prove that every Protobuf construct (like `repeated`, `map`, `enum`, nested messages, and timestamps) was mapped to the correct Iceberg type.

```bash
just -f protobuf-latest-scenario/justfile show-ddl product
just -f protobuf-latest-scenario/justfile show-ddl user
```

The `SHOW CREATE TABLE` output will reveal `array`, `map`, and `row` columns. You'll also see special `_choice` columns for `oneof` fields.

Run these helper queries to see the data in action:
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

### Step 7: Bonus - Schema Evolution Drill

To see how `by_latest_schema` handles changes dynamically, you can perform a quick schema evolution drill:

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
| `uint32`, `fixed32` | `int` | Iceberg does not natively support unsigned types; **large values may wrap/overflow.** |
| `int64`, `sint64`, `sfixed64` | `long` | Stored as signed long |
| `uint64`, `fixed64` | `long` | Iceberg does not natively support unsigned types; **beware of overflow.** |
| `float` | `float` | — |
| `double` | `double` | — |
| `bool` | `bool` | — |
| `string` | `string` | — |
| `bytes` | `binary` | — |
| `enum` | `string` | The symbol string value is stored. |
| `repeated` | `list` |  |
| `map` | `map` |  |
| `message` | `struct` | Proto2 `group` fields are not supported. |
| `google.protobuf.Timestamp` | `timestamp-micros` | Converted to microsecond timestamp (`timestamp(6)`). |


**Limitations**

* **Proto2 `group` fields** and **recursive** message definitions are **not supported**.
* **Unsigned integers** (`uint32`, `fixed32`, `uint64`, `fixed64`) do not have a native Iceberg equivalent. They are stored using the corresponding **signed type** (`int` or `long`), which may lead to **overflow or data corruption** if the values exceed the signed type's maximum range.

---

## Key Takeaways

* You ingested Protobuf data without embedding schema IDs—**Table Topic** fetched the schemas on demand.
* **Iceberg tables** were created automatically, correctly reflecting every `repeated`, `map`, `enum`, and **nested field** from your `.proto` files.
* Re-registering a new schema version **instantly and automatically** updates the table structure for future writes, **all without restarting any services**.
