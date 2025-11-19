# Scenario: Append-Only Ingestion

## 1. Scenario Objective

This scenario demonstrates how to stream Avro records into an Iceberg table using an **append-only** ingestion pattern. The server leverages Schema Registry to decode Avro messages and maps the Kafka record value fields into table columns before writing to Iceberg.

## 2. Core Configuration

Key Table Topic configs:
- `automq.table.topic.convert.value.type=by_schema_id`
- `automq.table.topic.transform.value.type=flatten`

## 3. Schema Design

### Order Schema (V1) - `schemas/Order.avsc`

Demonstrates all major Avro data types:

**Primitive Types:**
- `long`: order_id
- `string`: product_name, order_description, customer_email
- `double`: price
- `int`: quantity
- `boolean`: is_paid
- `float`: discount_rate
- `bytes`: payment_method

**Logical Types:**
- `timestamp-millis`: order_date (millisecond timestamp)
- `timestamp-micros`: created_at (microsecond timestamp)

**Complex Types:**
- `record`: shipping_address (nested Address record with street, city, postal_code)
- `enum`: order_status (PENDING, CONFIRMED, SHIPPED, DELIVERED, CANCELLED)
- `array`: product_tags (array of strings)
- `map`: custom_attributes (map<string, string>), product_prices (map<string, double>)

### OrderV2 Schema - `schemas/OrderV2.avsc`

Extends V1 with forward-compatible schema evolution patterns (see Step 5 for details).

### Schema Observation Checklist

| Concept | V1 fields | New in V2 | What to inspect |
| --- | --- | --- | --- |
| Primitive coverage | `order_id`, `product_name`, `price`, `quantity`, `is_paid`, `discount_rate`, `payment_method` | `total_amount`, `is_gift`, `loyalty_points_used` | `SHOW CREATE TABLE` → scalar columns |
| Logical timestamps | `order_date` (millis), `created_at` (micros) | `estimated_delivery_date` (nullable millis) | Compare timestamp precision in Trino |
| Complex / nested | `shipping_address`, `order_status`, `product_tags`, `custom_attributes`, `product_prices` | `billing_address`, `payment_status`, `related_order_ids`, `metadata` | `DESCRIBE TABLE` → `ROW/array/map` |
| Nullable unions | — | `tax_amount`, `shipping_fee`, `notes`, `gift_message`, `coupon_code` | Query V1 rows (expect `NULL`) vs V2 rows (values) |

Refer back to this table as you progress through the steps so every command is tied to a schema feature.

## 4. Steps to Run

This scenario demonstrates: write with the initial schema, then upgrade the schema and continue writing, and finally observe Iceberg's automatic schema evolution in the table.

### Step 1: Start Services

This command starts the base services required for the scenario, including Kafka, Schema Registry, and Trino.

```bash
just up
```

### Step 2: Create Table Topic

This command creates a Table Topic named `orders` with the required append-only configuration.

```bash
just -f append-scenario/justfile create-topic
```

### Step 3: Produce Initial Data (Schema v1)

Generate Avro data based on `schemas/Order.avsc` and send it to `orders`.

```bash
just -f append-scenario/justfile send-auto
```

### Step 4: View Table Info

Inspect table metadata and definition.

```bash
just -f append-scenario/justfile show-ddl
just -f append-scenario/justfile show-snapshots
just -f append-scenario/justfile show-history
just -f append-scenario/justfile show-files
just -f append-scenario/justfile show-manifests
```

Recommended verification query (captures enum, nested rows, arrays, and maps in a single glance):

```sql
SELECT order_id,
       order_status,
       shipping_address.city AS ship_city,
       product_tags,
       custom_attributes['loyalty-tier'] AS loyalty_tier,
       product_prices['usd'] AS usd_price
FROM iceberg.default.orders
ORDER BY order_id
LIMIT 5;
```

**Expected Output (after V1 schema):**

```sql
CREATE TABLE iceberg.default.orders (
   order_id bigint NOT NULL,
   product_name varchar NOT NULL,
   order_description varchar NOT NULL,
   customer_email varchar NOT NULL,
   price double NOT NULL,
   quantity integer NOT NULL,
   is_paid boolean NOT NULL,
   discount_rate real NOT NULL,
   payment_method varbinary NOT NULL,
   order_date timestamp(6) NOT NULL,
   created_at timestamp(6) NOT NULL,
   shipping_address ROW(street varchar, city varchar, postal_code varchar) NOT NULL,
   order_status varchar NOT NULL,
   product_tags array(varchar) NOT NULL,
   custom_attributes map(varchar, varchar) NOT NULL,
   product_prices map(varchar, double) NOT NULL,
   _kafka_header map(varchar, varbinary) COMMENT 'Kafka record headers',
   _kafka_key varchar COMMENT 'Kafka record key',
   _kafka_metadata ROW(partition integer, offset bigint, timestamp bigint) COMMENT 'Kafka record metadata'
)
```

Note: All V1 fields are `NOT NULL` as they have no default values in the schema.

### Step 5: Produce Data with Evolved Schema (V2)

Register and write data using an evolved schema (`schemas/OrderV2.avsc`) that demonstrates various types of **forward-compatible** schema changes:

#### Schema Evolution Changes in V2:

**1. Adding Fields with Default Values (Primitive Types)**
- `total_amount: double` (default: 0.0)
- `is_gift: boolean` (default: false)
- `loyalty_points_used: int` (default: 0)

**2. Adding Nullable Fields (Union with null)**
- `tax_amount: ["null", "double"]` (default: null)
- `shipping_fee: ["null", "double"]` (default: null)
- `notes: ["null", "string"]` (default: null)
- `gift_message: ["null", "string"]` (default: null)
- `coupon_code: ["null", "string"]` (default: null)
- `estimated_delivery_date: ["null", "long"]` with timestamp-millis (default: null)

**3. Adding Collection Types with Default Values**
- `related_order_ids: array<long>` (default: [])
- `metadata: map<string, string>` (default: {})

**4. Adding Complex Nested Records**
- `billing_address: ["null", BillingAddress]` (default: null)
  - New record type with fields: street, city, postal_code, country

**5. Adding New Enum Types**
- `payment_status: PaymentStatus` (default: "UNPAID")
  - Symbols: UNPAID, PAID, REFUNDED, PARTIALLY_REFUNDED

**Compatibility Guarantee:**
- V2 readers can read V1 data (missing fields use default values)
- V1 readers can read V2 data (ignore unknown fields)
- All changes maintain **full forward and backward compatibility**

```bash
just -f append-scenario/justfile send-auto-v2
```

### Step 6: View Table Info Again

```bash
just -f append-scenario/justfile show-ddl
just -f append-scenario/justfile show-snapshots
just -f append-scenario/justfile show-history
just -f append-scenario/justfile show-files
just -f append-scenario/justfile show-manifests
```

Use this query to contrast V1 vs V2 fields inside the data:

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

**Expected Output (after V2 schema evolution):**

```sql
CREATE TABLE iceberg.default.orders (
   order_id bigint NOT NULL,
   product_name varchar NOT NULL,
   order_description varchar NOT NULL,
   customer_email varchar NOT NULL,
   price double NOT NULL,
   quantity integer NOT NULL,
   is_paid boolean NOT NULL,
   discount_rate real NOT NULL,
   payment_method varbinary NOT NULL,
   order_date timestamp(6) NOT NULL,
   created_at timestamp(6) NOT NULL,
   shipping_address ROW(street varchar, city varchar, postal_code varchar) NOT NULL,
   order_status varchar NOT NULL,
   product_tags array(varchar) NOT NULL,
   custom_attributes map(varchar, varchar) NOT NULL,
   product_prices map(varchar, double) NOT NULL,
   _kafka_header map(varchar, varbinary) COMMENT 'Kafka record headers',
   _kafka_key varchar COMMENT 'Kafka record key',
   _kafka_metadata ROW(partition integer, offset bigint, timestamp bigint) COMMENT 'Kafka record metadata',
   -- New fields added by V2 schema evolution (nullable)
   total_amount double,
   is_gift boolean,
   loyalty_points_used integer,
   tax_amount double,
   shipping_fee double,
   notes varchar,
   gift_message varchar,
   coupon_code varchar,
   estimated_delivery_date timestamp(6),
   related_order_ids array(bigint),
   metadata map(varchar, varchar),
   billing_address ROW(street varchar, city varchar, postal_code varchar, country varchar),
   payment_status varchar
)
```

**Key Observations:**
- Original V1 fields remain `NOT NULL`
- All V2 fields are nullable (no `NOT NULL` constraint) because they have default values
- Schema evolution is **automatic** - Iceberg detects new fields and adds them to the table
- Old data (written with V1 schema) can still be read with the new V2 schema
- New data (written with V2 schema) includes the additional fields

### Step 7: Query Iceberg Data

Query the table to see all records across versions.

```bash
just -f append-scenario/justfile query
```

Optional: capture the DDL before and after Step 5 to see the column-level diff.

```bash
just -f append-scenario/justfile show-ddl > /tmp/orders_v1.sql   # run before Step 5
just -f append-scenario/justfile show-ddl > /tmp/orders_v2.sql   # run after Step 6
diff -u /tmp/orders_v1.sql /tmp/orders_v2.sql
```

## 5. Expected Outcome

1.  **Iceberg Table Creation**: An Iceberg table named `orders` is automatically created in the `iceberg.default` database with the V1 schema structure.

2.  **Data Ingestion (V1)**: Data sent with the V1 schema is successfully written to the `orders` table in an append-only fashion. All V1 fields are `NOT NULL`.

3.  **Schema Evolution (V2)**: When V2 data is written:
    - Iceberg automatically detects 13 new fields from the evolved schema
    - New fields are added as nullable columns (with default values)
    - No data migration required - old records retain their structure
    - Schema compatibility is maintained bidirectionally

4.  **Query Verification**: 
    - Queries return all records across both schema versions
    - V1 records show `NULL` for V2-only fields
    - V2 records contain values for all fields (or defaults)
    - No data loss or corruption occurs during evolution

5.  **Demonstrated Avro Types**:
    - **V1**: All basic types (long, string, double, int, boolean, float, bytes), logical types (timestamps), complex types (record, enum, array, map)
    - **V2**: Additional nullable fields, collections with defaults, new nested records, new enums

## 6. Cross-Scenario Tip

Pair this Avro workflow with the Protobuf latest-schema scenario. Running both back-to-back shows how `by_schema_id` (Avro) and `by_latest_schema` (Protobuf) surface schema evolution in Iceberg while using the same inspection commands (`show-ddl`, `show-files`, `query`). Document the differences for your team using the observation checklist above.

## 7. Cleanup

Run the following command to stop and remove all Docker containers started for this scenario.

```bash
just down
```
