# Scenario: Protobuf Ingestion with Latest Schema

## 1. Scenario Objective

This scenario demonstrates how to ingest raw **Protobuf** messages into an Iceberg table. Unlike Avro, these messages are not framed with a schema ID. Instead, the server decodes the raw Protobuf bytes by fetching the **latest registered schema** for a specific subject from the Schema Registry.

## 2. Core Configuration

This scenario relies on the following key Table Topic configurations for server-side Protobuf decoding:
- `automq.table.topic.convert.value.type=by_latest_schema`: Instructs the server to decode the message payload by fetching the latest schema version associated with a given subject.
- `automq.table.topic.convert.value.subject`: Specifies the subject name in Schema Registry to look up (e.g., `product-value`).
- `automq.table.topic.convert.value.message.full.name`: Specifies the fully qualified name of the Protobuf message type to use for decoding
- `automq.table.topic.transform.value.type=flatten`: Map the fields inside the Kafka record's value into top-level table columns (the key is not used for column mapping).

## 3. Steps to Run

Follow these steps to run the demonstration.

### Step 1: Start Services

This command starts the base services required for the scenario.

```bash
just up
```

### Step 2: Register Protobuf Schemas

This command uses a Maven plugin to compile and register the `.proto` schema files (`user.proto`, `product.proto`) with the Schema Registry. This step is required so the server can fetch them later for decoding.

```bash
just -f protobuf-latest-scenario/justfile register
```

### Step 3: Create Table Topics

These commands create two Table Topics, `product` and `user`, each configured to use the latest schema of a specific subject for decoding.

```bash
# Create the 'product' topic
just -f protobuf-latest-scenario/justfile create-product-topic

# Create the 'user' topic
just -f protobuf-latest-scenario/justfile create-user-topic
```

### Step 4: Produce Raw Protobuf Data

These commands produce raw, unframed Protobuf messages to their respective topics.

```bash
# Produce a product record
just -f protobuf-latest-scenario/justfile send-product-raw

# Produce a user record
just -f protobuf-latest-scenario/justfile send-user-raw
```

### Step 5: View Table DDL

Inspect the table definitions created for the topics.

```bash
# DDL for the 'product' table
just -f protobuf-latest-scenario/justfile show-ddl product

# DDL for the 'user' table
just -f protobuf-latest-scenario/justfile show-ddl user
```

### Step 6: View Table Info

Inspect table metadata via Iceberg metadata tables.

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

### Step 7: Query Iceberg Data

Query the newly created Iceberg tables via Trino to see the structured, decoded data.

```bash
# Query the 'product' table
just -f protobuf-latest-scenario/justfile query-product

# Query the 'user' table
just -f protobuf-latest-scenario/justfile query-user
```

## 4. Expected Outcome

1.  **Schemas Registered**: The `product-value` and `user-value` subjects are successfully registered in Schema Registry.
2.  **Iceberg Table Creation**: Two Iceberg tables, `product` and `user`, are created in the `iceberg.default` database.
3.  **Server-Side Decoding**: The Table Topic service successfully decodes the raw Protobuf byte streams by fetching the latest schemas from Schema Registry and maps the Kafka record value fields into the corresponding tables.
4.  **Query Verification**: Queries against the `product` and `user` tables in Trino return structured, readable data.

## 5. Cleanup

Run the following command to stop and remove all Docker containers started for this scenario.

```bash
just down
```
