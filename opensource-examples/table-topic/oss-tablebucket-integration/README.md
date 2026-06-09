# AutoMQ Table Topic with Aliyun OSS Tables

This example shows how to write Avro messages from AutoMQ Table Topic into Aliyun OSS Tables.

It covers two AutoMQ catalog modes:

- OSS Tables REST Catalog
- OSS S3 Tables Catalog

AutoMQ uses local MinIO for its own stream storage in this example. Table Topic writes Iceberg metadata and data to Aliyun OSS Tables / OSS. Spark SQL is included for querying the resulting Iceberg tables through the OSS Tables REST Catalog.

For the catalog settings used by each mode, see [CATALOG_CONFIG.md](CATALOG_CONFIG.md).

## Prerequisites

- Docker
- `just`
- An Aliyun OSS Tables Table Bucket
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

Query the table with Spark SQL:

```bash
just query-rest
```

## Run with OSS S3 Tables Catalog

Start the environment:

```bash
just up-tablebucket
```

Create the Table Topic, produce Avro records, and wait for a successful Table Topic commit:

```bash
just test-tablebucket
```

By default this writes to the `orders_tablebucket` table in `TABLE_TOPIC_NAMESPACE`.

The `tablebucket` command and compose names match AutoMQ's `automq.table.topic.catalog.type=tablebucket` configuration value. The catalog path itself is the S3 Tables Catalog-compatible path.

Query the table with Spark SQL:

```bash
just query-tablebucket
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
just spark-sql-rest "SHOW TABLES IN oss_tables.automq_it"
just spark-sql-tablebucket "SHOW TABLES IN oss_tables.automq_it"
just down
```

## Cleanup

Stop local containers and remove local volumes:

```bash
just down
```

This does not delete remote tables or data in Aliyun OSS Tables / OSS. Delete remote test tables from your Aliyun environment when they are no longer needed.
