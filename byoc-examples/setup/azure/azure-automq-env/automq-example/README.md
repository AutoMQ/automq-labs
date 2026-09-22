# Manage AutoMQ Resources on Azure with Terraform

This example uses the `automq/automq` provider to create a Kafka Instance and a
Debezium JDBC Sink Connector for PostgreSQL after the Azure BYOC environment
is ready.

The example contains two independent Terraform configurations:

| Directory | Resources |
| --- | --- |
| [instance/](instance/main.tf) | A three-zone, three-node Kafka Instance with S3WAL, SASL_PLAINTEXT, and usage-based pricing |
| [connector/](connector/main.tf) | A Debezium JDBC plugin, Connect Cluster, Connector, and the Kafka topic, user, and ACLs needed to consume orders into PostgreSQL |

Each configuration has its own Terraform state. Set environment-specific values
in the `locals` block at the top of each `main.tf`.

## Prerequisites

- Terraform 1.3 or later.
- A completed [Azure BYOC environment setup](../README.md) and Console System
  Initialization.
- An AKS node pool spanning three availability zones with sufficient capacity.
- A Console and Data Plane version that supports Azure AKS, S3WAL, usage-based
  pricing, and Managed Connect.

The examples use AutoMQ provider 0.4.8. Confirm Azure compatibility with your
target version before deployment; the provider documentation does not yet list
an Azure minimum Control Plane version. Live Azure deployment has not been
verified for these examples.

## Configure

Sign in to the AutoMQ Console, open **Service Accounts**, and create a Service
Account with permissions to manage the example resources. Create and download
its Access Key ID (AK) and Secret Access Key (SK). See
[Service Accounts](https://docs.automq.com/automq-cloud/manage-identities-and-access/service-accounts).

Export the Control Plane endpoint and credentials:

```bash
export AUTOMQ_BYOC_ENDPOINT="<console-endpoint>"
export AUTOMQ_BYOC_ACCESS_KEY="<service-account-access-key>"
export AUTOMQ_BYOC_SECRET_KEY="<service-account-secret-key>"
```

These credentials authenticate Terraform requests to AutoMQ. Kafka clients and
PostgreSQL use separate credentials. Keep credentials, state, and saved plans
out of version control.

## Create a Kafka Instance

Edit the `locals` block in [instance/main.tf](instance/main.tf):

- Set the environment ID and a supported Data Plane version.
- Set the AKS cluster and load balancer subnet full ARM resource IDs.
- Set the instance type, node pool name, and three zone IDs from your environment.

The configuration selects `K8S` deployment, `UsageBased` pricing, and three
AutoMQ nodes. `S3WAL` uses Azure Blob for object-storage WAL.
`SASL_PLAINTEXT` provides authentication over an unencrypted private connection.

The Control Plane creates and manages the Data Bucket, Data Plane identity
(UAMI), and Private DNS Zone because `data_buckets`, `instance_role`, and
`dns_zone` are omitted. AKS, networking, and the environment Ops Bucket are
reused from the environment setup.

Scheduling uses the existing AutoMQ node pool and its
`dedicated=automq:NoSchedule` taint. Workload zones come from the node pool;
the load balancer subnet is configured separately.

From this directory, run:

```bash
cd instance
terraform init
terraform plan
terraform apply
terraform output -raw instance_id
terraform output endpoints
```

## Create a Debezium JDBC Sink

The Connector uses `io.debezium.connector.jdbc.JdbcSinkConnector` to consume the
three-partition `orders` topic and upsert rows into PostgreSQL by `order_id`.
It runs one task on a Connect Cluster with one `TIER1` worker.

### Prepare PostgreSQL and the Plugin

Prepare a PostgreSQL database accessible from Connect workers and create the
target table:

```sql
CREATE TABLE public.orders (
    order_id BIGINT PRIMARY KEY,
    customer_id TEXT NOT NULL,
    amount DOUBLE PRECISION NOT NULL
);
```

Grant the database user CONNECT, schema USAGE, and SELECT/INSERT/UPDATE
permissions. Its search path must resolve `orders` to this table. The example
uses the existing table with automatic creation and schema evolution disabled.

Host a compatible Debezium JDBC plugin ZIP, including the PostgreSQL JDBC
driver, at an HTTPS URL accessible to the Console and Connect runtime. See the
[Debezium JDBC documentation](https://debezium.io/documentation/reference/3.2/connectors/jdbc.html)
for packaging and configuration requirements.

### Configure and Create

Edit the `locals` block in [connector/main.tf](connector/main.tf). Set the
environment and Instance IDs, AKS settings, plugin URL and version, Kafka
password, and PostgreSQL connection details.

Use a namespace and ServiceAccount supported by your Connect configuration.
If the runtime requires Azure Workload Identity, prepare the worker identity,
federation, and grants according to the target version's documentation, including
`compute.iam_role` where required.

The configuration creates a `jdbc-reader` Kafka user with topic CONSUME
permission and access to the Connector's consumer group. The user and Connector
share `local.kafka_password`. The PostgreSQL password is supplied through
`connector_config_sensitive` and are retained in Terraform state.

From `instance/`, run:

```bash
cd ../connector
terraform init
terraform plan
terraform apply
terraform output connector_state
```

### Verify

Use a Kafka producer with PRODUCE permission on `orders`. The configured
JsonConverter expects a schema/payload envelope. Send the following JSON as a
single record value:

```json
{
  "schema": {
    "type": "struct",
    "name": "Order",
    "optional": false,
    "fields": [
      { "field": "order_id", "type": "int64", "optional": false },
      { "field": "customer_id", "type": "string", "optional": false },
      { "field": "amount", "type": "float64", "optional": false }
    ]
  },
  "payload": {
    "order_id": 1001,
    "customer_id": "customer-1",
    "amount": 42.5
  }
}
```

Check Connector task health in the Console and verify the row in PostgreSQL:

```sql
SELECT * FROM public.orders WHERE order_id = 1001;
```

The Connector uses `primary.key.mode = record_value`,
`primary.key.fields = order_id`, and `schema.evolution = none`.
Replaying the same `order_id` updates the existing row. The group ACL follows
`local.connector_name`; update the ACL if you configure a custom consumer group.

## Cleanup

Destroy Connector resources before the Kafka Instance:

```bash
# From connector/
terraform destroy
cd ../instance
terraform destroy
```

The PostgreSQL database and its rows remain in place. Remove environment
infrastructure separately after reviewing data retention requirements.

## References

Refer to the provider documentation when adapting these examples:

- [Provider](https://registry.terraform.io/providers/automq/automq/0.4.8/docs)
- [Kafka Instance](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/kafka_instance)
- [Kafka Topic](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/kafka_topic)
- [Kafka User](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/kafka_user)
- [Kafka ACL](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/kafka_acl)
- [Connector Plugin](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/connector_plugin)
- [Connect Cluster](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/connect_cluster)
- [Connector](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/connector)
