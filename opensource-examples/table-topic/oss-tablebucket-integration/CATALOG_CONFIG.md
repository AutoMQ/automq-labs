# Catalog Configuration

This document describes the catalog settings used by the `oss-tablebucket-integration` example.

## Environment Variables

The example reads Aliyun settings from `.env`:

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

`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, and `AWS_DEFAULT_REGION` use AWS SDK-compatible names because the Iceberg catalog and file I/O libraries use AWS SDK credential providers.

## AutoMQ with OSS Tables REST Catalog

`docker-compose.automq-rest.yml` configures AutoMQ Table Topic to use the OSS Tables REST Catalog:

```properties
automq.table.topic.catalog.type=rest
automq.table.topic.catalog.uri=${OSS_ICEBERG_REST_URI}
automq.table.topic.catalog.warehouse=${OSS_TABLE_BUCKET_ARN}
automq.table.topic.catalog.rest.sigv4-enabled=true
automq.table.topic.catalog.rest.signing-region=${AWS_REGION}
automq.table.topic.catalog.rest.signing-name=osstables
automq.table.topic.catalog.client.region=${AWS_REGION}
automq.table.topic.catalog.client.credentials-provider=software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider
automq.table.topic.catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO
automq.table.topic.catalog.s3.endpoint=${OSS_ENDPOINT}
automq.table.topic.catalog.s3.path-style-access=false
automq.table.topic.namespace=${TABLE_TOPIC_NAMESPACE}
automq.table.topic.schema.registry.url=http://schema-registry:8081
```

`warehouse` is the OSS Tables Table Bucket ARN.

## AutoMQ with OSS S3 Tables Catalog

`docker-compose.automq-tablebucket.yml` configures AutoMQ Table Topic to use the OSS S3 Tables Catalog-compatible path:

```properties
automq.table.topic.catalog.type=tablebucket
automq.table.topic.catalog.warehouse=${OSS_TABLE_BUCKET_ARN}
automq.table.topic.catalog.s3tables.endpoint=${OSS_TABLES_ENDPOINT}
automq.table.topic.catalog.client.region=${AWS_REGION}
automq.table.topic.catalog.client.credentials-provider=software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider
automq.table.topic.catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO
automq.table.topic.catalog.s3.endpoint=${OSS_ENDPOINT}
automq.table.topic.catalog.s3.path-style-access=false
automq.table.topic.namespace=${TABLE_TOPIC_NAMESPACE}
automq.table.topic.schema.registry.url=http://schema-registry:8081
```

This mode maps to the S3 Tables Catalog implementation path used by `awslabs/s3-tables-catalog`, exposed in AutoMQ as `automq.table.topic.catalog.type=tablebucket`.

The `s3.endpoint` and `s3.path-style-access=false` settings are required by `S3FileIO` when it writes Iceberg metadata and data files to Aliyun OSS.

## Spark Catalog

The Spark SQL commands configure an Iceberg REST catalog named `oss_tables`:

```properties
spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions
spark.sql.catalog.oss_tables=org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.oss_tables.type=rest
spark.sql.catalog.oss_tables.uri=${OSS_ICEBERG_REST_URI}
spark.sql.catalog.oss_tables.warehouse=${OSS_TABLE_BUCKET_ARN}
spark.sql.catalog.oss_tables.rest.sigv4-enabled=true
spark.sql.catalog.oss_tables.rest.signing-name=osstables
spark.sql.catalog.oss_tables.rest.signing-region=${AWS_REGION}
spark.sql.catalog.oss_tables.client.region=${AWS_REGION}
spark.sql.catalog.oss_tables.client.credentials-provider=software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider
spark.sql.catalog.oss_tables.io-impl=org.apache.iceberg.aws.s3.S3FileIO
spark.sql.catalog.oss_tables.s3.endpoint=${OSS_ENDPOINT}
spark.sql.catalog.oss_tables.s3.path-style-access=false
```

Spark uses Iceberg's `S3FileIO` for data reads, so it can query tables written by both AutoMQ catalog modes through the OSS Tables REST Catalog.
