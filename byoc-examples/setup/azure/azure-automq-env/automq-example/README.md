# Manage AutoMQ Resources on Azure with Terraform

These examples show how to use the `automq/automq` provider after completing
the [Azure BYOC environment setup](../README.md) and Console System Initialization.
Edit the placeholders directly in each `main.tf`; these are standalone examples,
not reusable modules.

- [instance/main.tf](instance/main.tf): create a three-zone, three-node Kafka
  Instance with S3WAL, SASL_PLAINTEXT, and usage-based pricing.
- [connector/main.tf](connector/main.tf): consume the `orders` topic into
  PostgreSQL using a JDBC Sink Connector.

The examples use provider 0.4.8. Confirm that your Console/Data Plane versions
support these Azure capabilities, including Managed Connect. The provider
documentation does not yet specify an Azure minimum Control Plane version.
These examples have not been tested against a live Azure environment.

## Configure

Sign in to the AutoMQ Console and open **Service Accounts**. Create a Service
Account with the required resource permissions, then create/download its Access
Key ID (AK) and Secret Access Key (SK). See
[Service Accounts](https://docs.automq.com/automq-cloud/manage-identities-and-access/service-accounts).

Export the environment's Control Plane endpoint and Service Account credentials:

```bash
export AUTOMQ_BYOC_ENDPOINT="<console-endpoint>"
export AUTOMQ_BYOC_ACCESS_KEY="<service-account-access-key>"
export AUTOMQ_BYOC_SECRET_KEY="<service-account-secret-key>"
```

Provider 0.4.8 reads `AUTOMQ_BYOC_ACCESS_KEY`, not `AUTOMQ_BYOC_ACCESS_KEY_ID`.
These API credentials are separate from Kafka SASL and PostgreSQL credentials.
Do not commit real credentials, Terraform state, or saved plans.

## Create a Kafka Instance

In `instance/main.tf`, replace the environment ID, supported **Data Plane**
version, AKS cluster and load balancer subnet full ARM IDs, instance type,
node pool name, and three AZ identifiers with values from your environment.

| Setting | Example |
| --- | --- |
| Deployment | Existing AKS cluster, `K8S` |
| Pricing | `UsageBased` |
| AutoMQ nodes | `reserved_node_count = 3` |
| Placement | Three zones supported by the AKS node pool |
| WAL | `S3WAL`, backed by Azure Blob |
| Authentication / transport | `sasl` / `plaintext` |

The example deliberately omits `data_buckets`, `instance_role`, and `dns_zone`.
The Control Plane creates and manages the Data Bucket, Data Plane UAMI, and
Private DNS Zone. Do not fill in the environment setup's customer-provided
bucket, identity, or DNS outputs.

AKS, its node pool, networking, and the environment Ops Bucket are existing
dependencies. The scheduling settings use the node pool label and
`dedicated=automq:NoSchedule` taint from the environment example. Azure subnets
are regional; workload placement uses node pool zones, not per-zone subnets.
SASL_PLAINTEXT assumes private network access and does not encrypt traffic.

```bash
cd instance
terraform init
terraform plan
terraform apply
terraform output -raw instance_id
terraform output endpoints
```

## Create a PostgreSQL JDBC Sink

The Connector example creates:

- An `orders` topic with three partitions.
- A `jdbc-reader` Kafka user, topic CONSUME permission, and access to consumer
  group `connect-demo-orders-postgres`.
- A JDBC plugin registration and a one-worker `TIER1` Connect Cluster.
- A one-task `io.confluent.connect.jdbc.JdbcSinkConnector` that upserts orders
  into PostgreSQL using `order_id` as the primary key.

Prepare a complete JDBC plugin ZIP, including the PostgreSQL JDBC driver,
compatible with your Connect runtime. Supply an HTTPS download URL reachable
by the Console/runtime. The example registers the archive; it does not build
or upload it. See the
[JDBC Sink documentation](https://docs.confluent.io/kafka-connectors/jdbc/current/sink-connector/overview.html).

Prepare a PostgreSQL database reachable from Connect workers and create:

```sql
CREATE TABLE public.orders (
    order_id BIGINT PRIMARY KEY,
    customer_id TEXT NOT NULL,
    amount DOUBLE PRECISION NOT NULL
);
```

Give the database user CONNECT, schema USAGE, and SELECT/INSERT/UPDATE permissions.
Ensure its search path resolves `orders` to this table. The example disables
automatic table creation and schema evolution.

Replace the placeholders in `connector/main.tf`, including the Instance ID
from the previous step, AKS settings, plugin URL/version, Kafka password, and
database connection details. Use the same Kafka password in the user and
Connector resources. The database password is shown in
`connector_config_sensitive` to demonstrate that API field; sensitive values
still appear in Terraform state.

Confirm the Connect namespace, ServiceAccount, capacity, and network requirements
for your target environment. If the worker runtime needs Azure Workload Identity,
configure its identity, federation, and grants according to the target version's
documentation, including `compute.iam_role` when required. The Instance identity
is not automatically the Connect worker identity.

```bash
# From instance/
cd ../connector
terraform init
terraform plan
terraform apply
terraform output connector_state
```

Produce records to `orders` using a separate Kafka user with PRODUCE permission.
The JsonConverter in this example requires a schema/payload envelope, not plain
JSON. Send the following as one Kafka record value:

```json
{"schema":{"type":"struct","name":"Order","optional":false,"fields":[{"field":"order_id","type":"int64","optional":false},{"field":"customer_id","type":"string","optional":false},{"field":"amount","type":"float64","optional":false}]},"payload":{"order_id":1001,"customer_id":"customer-1","amount":42.5}}
```

Check Connector/task health in the Console, then query PostgreSQL:

```sql
SELECT * FROM public.orders WHERE order_id = 1001;
```

The record key is ignored; replaying the same `order_id` updates the existing row.
If you change the Connector name or override its consumer group, also update
the group ACL.

## Cleanup

The examples have separate Terraform state. Destroy Connector resources first,
then the Kafka Instance:

```bash
# From connector/
terraform destroy
cd ../instance
terraform destroy
```

The external PostgreSQL database and rows are not managed by these examples.
Clean up environment infrastructure last, after checking data retention needs.

## Reference

Use the provider documentation for complete schemas, version compatibility,
permissions, and update/import behavior:

- [Provider](https://registry.terraform.io/providers/automq/automq/0.4.8/docs)
- [Kafka Instance](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/kafka_instance)
- [Kafka Topic](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/kafka_topic),
  [Kafka User](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/kafka_user),
  [Kafka ACL](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/kafka_acl)
- [Connector Plugin](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/connector_plugin)
- [Connect Cluster](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/connect_cluster)
- [Connector](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/connector)
