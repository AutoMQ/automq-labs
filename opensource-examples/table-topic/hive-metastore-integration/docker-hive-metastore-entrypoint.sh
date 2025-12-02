#!/bin/bash
set -e

echo "Checking if MySQL is ready..."
until mysql -h mysql -u hive -phive -D metastore -e "SELECT 1;" &>/dev/null; do
  echo "Waiting for MySQL to be ready..."
  sleep 5
done

echo "Checking if Hive Metastore schema exists..."
if ! mysql -h mysql -u hive -phive -D metastore -e "SELECT * FROM VERSION;" &>/dev/null; then
  echo "Schema not found. Initializing Hive Metastore schema..."
  /opt/hive/bin/schematool -initSchema -dbType mysql
else
  echo "Schema already exists. Skipping initialization."
fi

echo "Starting Hive Metastore..."
exec /opt/hive/bin/hive --service metastore
