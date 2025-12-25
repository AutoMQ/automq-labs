# Debezium RDS Test Environment

This directory contains Terraform configuration for provisioning an AWS RDS MySQL or PostgreSQL instance that satisfies Debezium CDC requirements.

## Layout

- `terraform/`: Terraform module that builds the entire environment (VPC, networking, security group, RDS instance).

## Usage

```bash
cd terraform
terraform init
terraform apply -var='database_type=mysql'
# or
terraform apply -var='database_type=postgresql'

# Retrieve the generated password after apply
terraform output -raw database_password
```

Destroy the environment when finished:

```bash
terraform destroy -var='database_type=mysql'
# or
terraform destroy -var='database_type=postgresql'
```

## Database Configuration Details

### MySQL

- **Username**: `admin`
- **Port**: `3306`
- **Binary logging**: Automatically enabled by RDS when backups are enabled
- **Parameters**: `binlog_format=ROW`, `binlog_row_image=FULL`, `binlog_checksum=NONE`

### PostgreSQL

- **Username**: `dbadmin` (Note: `admin` is reserved in PostgreSQL)
- **Port**: `5432`
- **Logical replication**: Enabled via `rds.logical_replication=1`
- **Parameters**: `max_replication_slots=10`, `max_wal_senders=10`

The Terraform module relies on the AWS default MySQL 8.0 and PostgreSQL 15 engine versions so there is no need to pin a patch release manually.

For MySQL, Amazon RDS manages binary logging automatically when backups are enabled, so parameters like `log_bin` or `binlog_expire_logs_seconds` cannot be changed in a custom group. After apply you can adjust retention with: `CALL mysql.rds_set_configuration('binlog retention hours', 24);`.

For PostgreSQL, the `wal_level` parameter is automatically managed by RDS and set to `logical` when `rds.logical_replication` is enabled.

## Debezium Setup (PostgreSQL Only)

After creating the PostgreSQL database, additional setup is required for Debezium CDC:

### 1. Connect to the Database
```bash
# Get the connection details
terraform output database_endpoint
terraform output -raw database_password

# Connect using psql
psql -h <endpoint> -p 5432 -U dbadmin -d testdb
```

### 2. Run Debezium Setup Script
```sql
-- The setup_debezium_user.sql script will:
-- 1. Create a dedicated 'debezium' user with replication privileges
-- 2. Grant necessary permissions for CDC
-- 3. Create a test table with sample data
-- 4. Verify logical replication settings

\i setup_debezium_user.sql
```

### 3. Verify Configuration
```sql
-- Check that logical replication is enabled
SHOW rds.logical_replication;  -- Should be 'on'
SHOW max_replication_slots;    -- Should be 20
SHOW max_wal_senders;          -- Should be 20

-- List available logical replication slots
SELECT slot_name, plugin, slot_type, database, active FROM pg_replication_slots;
```

### 4. Debezium Connector Configuration
Use these settings in your Debezium PostgreSQL connector:

```json
{
  "name": "postgres-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "<your-endpoint>",
    "database.port": "5432",
    "database.user": "debezium",
    "database.password": "debezium_password_change_me",
    "database.dbname": "testdb",
    "database.server.name": "postgres-server",
    "plugin.name": "pgoutput",
    "publication.autocreate.mode": "all_tables",
    "schema.include.list": "public",
    "table.include.list": "public.customers"
  }
}
```

**Note**: The RDS PostgreSQL instance is configured with:
- Logical replication enabled
- pgoutput plugin (built-in, no additional installation needed)
- Appropriate connection limits and performance settings

