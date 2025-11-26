#!/bin/bash

# wait for MinIO service to start
until (/usr/bin/mc alias set minio http://storage:9000 admin password) do echo '...waiting...' && sleep 1; done;

# create iceberg bucket
/usr/bin/mc mb minio/iceberg

# set iceberg bucket to public read
/usr/bin/mc anonymous set public minio/iceberg

/usr/bin/mc rm -r --force minio/warehouse;
/usr/bin/mc mb minio/warehouse;
/usr/bin/mc anonymous set public minio/warehouse;

/usr/bin/mc rm -r --force minio/automq-data;
/usr/bin/mc mb minio/automq-data;
/usr/bin/mc anonymous set public minio/automq-data;

/usr/bin/mc rm -r --force minio/automq-ops;
/usr/bin/mc mb minio/automq-ops;
/usr/bin/mc anonymous set public minio/automq-ops;

tail -f /dev/null
