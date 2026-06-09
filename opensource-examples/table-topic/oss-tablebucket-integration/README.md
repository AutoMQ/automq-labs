# AutoMQ Table Topic with Aliyun OSS TableBucket

This example shows how to write Avro messages from AutoMQ Table Topic into Aliyun OSS Tables.

It covers two AutoMQ catalog modes:

- OSS Tables REST Catalog
- OSS TableBucket Catalog

AutoMQ uses local MinIO for its own stream storage in this example. Table Topic writes Iceberg metadata and data to Aliyun OSS Tables / OSS. Trino is included for querying the resulting Iceberg tables through the OSS Tables REST Catalog.

For the catalog settings used by each mode, see [CATALOG_CONFIG.md](CATALOG_CONFIG.md).

## Prerequisites

- Docker
- `just`
- An Aliyun OSS TableBucket
- AK/SK with permission to access OSS Tables and OSS
- Public network access to the configured Aliyun endpoints

## Configure

Create a local `.env` file:

```bash
cp .env.example .env
```

Fill in the Aliyun credentials and resource settings:

```env
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_REGION=cn-hangzhou
AWS_DEFAULT_REGION=cn-hangzhou
OSS_TABLE_BUCKET_ARN=acs:osstables:cn-hangzhou:<account-id>:bucket/<table-bucket>
OSS_TABLES_ENDPOINT=https://cn-hangzhou.oss-tables.aliyuncs.com
OSS_ICEBERG_REST_URI=https://cn-hangzhou.oss-tables.aliyuncs.com/iceberg
OSS_ENDPOINT=https://oss-cn-hangzhou.aliyuncs.com
TABLE_TOPIC_NAMESPACE=automq_it
```

## Run with OSS Tables REST Catalog

Start the environment:

```bash
just up-rest
```

Create the Table Topic, produce Avro records, and wait for a successful Table Topic commit:

```bash
just test-rest
```

By default this writes to the `orders_rest` table in `TABLE_TOPIC_NAMESPACE`.

Query the table with Trino:

```bash
just trino-sql-rest "SELECT * FROM automq_it.orders_rest LIMIT 10"
```

## Run with OSS TableBucket Catalog

Start the environment:

```bash
just up-tablebucket
```

Create the Table Topic, produce Avro records, and wait for a successful Table Topic commit:

```bash
just test-tablebucket
```

By default this writes to the `orders_tablebucket` table in `TABLE_TOPIC_NAMESPACE`.

Query the table with Trino:

```bash
just trino-sql-tablebucket "SELECT * FROM automq_it.orders_tablebucket LIMIT 10"
```

## Custom Topic Names

The default table names make the two catalog modes easy to compare. You can override them:

```bash
just test-rest my_rest_table 20
just test-tablebucket my_tablebucket_table 20
```

## Useful Commands

```bash
just status-rest
just status-tablebucket
just logs-rest automq
just logs-tablebucket automq
just down
```

## Cleanup

Stop local containers and remove local volumes:

```bash
just down
```

This does not delete remote tables or data in Aliyun OSS Tables / OSS. Delete remote test tables from your Aliyun environment when they are no longer needed.
