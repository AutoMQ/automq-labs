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
```


The Terraform module relies on the AWS default MySQL 8.0 and PostgreSQL 15 engine versions so there is no need to pin a patch release manually.

For MySQL, Amazon RDS manages binary logging automatically when backups are enabled, so parameters like `log_bin` or `binlog_expire_logs_seconds` cannot be changed in a custom group. After apply you can adjust retention with: `CALL mysql.rds_set_configuration('binlog retention hours', 24);`.

