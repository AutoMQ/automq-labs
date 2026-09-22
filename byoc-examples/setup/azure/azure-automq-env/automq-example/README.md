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

For this example, we want a Kafka cluster on the AKS infrastructure created
during environment setup. The cluster should have three AutoMQ nodes across
three availability zones, use object storage for WAL, and use pay-as-you-go
pricing. Clients will connect over the private network using SASL_PLAINTEXT.
AutoMQ will create and manage the cluster's data storage, identity, and DNS zone.

### Choose the Instance Configuration

These deployment choices determine the fields in
[`automq_kafka_instance.demo`](instance/main.tf):

| Deployment choice | Terraform configuration |
| --- | --- |
| Run on the existing AKS cluster | Set `compute_specs.deploy_type = "K8S"` and select the cluster with `kubernetes_cluster_id`. |
| Use pay-as-you-go pricing with three AutoMQ nodes | Set `pricing_mode = "UsageBased"` and `reserved_node_count = 3`. |
| Place workloads across three AZs | Populate `networks` with three zone IDs supported by the selected node pool. |
| Use object-storage WAL | Set `features.wal_mode = "S3WAL"`; in Azure, this uses Azure Blob. |
| Authenticate clients using SASL_PLAINTEXT | Set `authentication_methods = ["sasl"]` and `transit_encryption_modes = ["plaintext"]` under `features.security`. |
| Let AutoMQ manage storage, identity, and DNS | Omit `data_buckets`, `instance_role`, and `dns_zone` from `compute_specs`. (If you do not want CMP to have permission to create these resources, prepare customer-provided resources that meet the documented requirements and explicitly supply these fields; CMP still needs the permissions required to use them.) |

Omitting those managed-resource fields lets the Control Plane create the Data
Bucket, Data Plane UAMI, and Private DNS Zone when it creates the Instance.
The existing AKS cluster, networking, and environment Ops Bucket remain the
foundation for the deployment.

The Instance also needs a node size and a scheduling target. `instance_types`
selects a supported compute specification, while `schedule_spec` selects the
AutoMQ node pool and tolerates its `dedicated=automq:NoSchedule` taint. The node
pool must have capacity in all three selected zones. Three AutoMQ nodes refer
to the Instance size, not the total number of AKS VMs.

SASL_PLAINTEXT provides authentication without transport encryption. This
example assumes private network access; choose a TLS configuration if your
deployment requires encrypted client connections.

### Supply the Environment Details

The deployment choices above are already written into the resource. To apply
them to your environment, fill in the `locals` block at the top of
[instance/main.tf](instance/main.tf):

| Local value | Information to provide |
| --- | --- |
| `environment_id` | The Azure BYOC Environment ID from the Console's System Settings. |
| `automq_version` | A Data Plane version offered by the Console for this environment, rather than the Console's own version. |
| `kubernetes_cluster_id` | The existing AKS cluster's full ARM resource ID; the environment setup exposes it as `kubernetes_cluster_id`. |
| `instance_type` | A supported Instance type compatible with the selected node pool. |
| `node_pool_name` | The dedicated AKS node pool name; the environment setup exposes it as `automq_nodepool_name`. |
| `zones` | Three AZ identifiers returned for the selected node pool in the Console. |
| `load_balancer_subnet_id` | The full ARM resource ID of the subnet used for the Instance's private load balancer. |

Azure subnets are regional. This K8S example leaves `networks[].subnets` empty
and takes workload placement from the node pool's zones. The load balancer
subnet is supplied separately through `kubernetes_load_balancer_subnets`.

The resource references these local values so each environment detail is
entered once. The Service Account credentials configured earlier authorize
Terraform to submit the resulting Instance configuration to AutoMQ.

### Create and Check the Instance

From this directory, initialize Terraform and review the plan. Check that it
creates the intended Instance in your environment, then apply it:

```bash
cd instance
terraform init
terraform plan
terraform apply
terraform output -raw instance_id
terraform output endpoints
```

Check the Instance status and node placement in the Console. Save the
`instance_id` output for the Connector example below. For additional options
and update behavior, see the
[Kafka Instance resource documentation](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/kafka_instance).

## Create a Debezium JDBC Sink

Next, we want to send order events from the Kafka Instance to PostgreSQL.
Each event contains an `order_id`, `customer_id`, and `amount`. PostgreSQL should
keep one row per order, updating that row when another event arrives with the
same `order_id`. The database table will be prepared in advance.

For this small example, we will use a three-partition `orders` topic and run
one Sink task on a Connect Cluster with one `TIER1` worker. The data flow is
`orders` topic → Debezium JDBC Sink → PostgreSQL `public.orders` table.

### Choose the Resources and Configuration

This data flow needs a plugin that understands JDBC, workers to run it, and a
Connector configuration describing what to read and where to write. These map
to three resources in [connector/main.tf](connector/main.tf):

| Resource | Role in the example |
| --- | --- |
| `automq_connector_plugin.jdbc` | Registers the Debezium JDBC archive and its `io.debezium.connector.jdbc.JdbcSinkConnector` class as a `SINK` plugin. |
| `automq_connect_cluster.demo` | Runs the workers on AKS, installs the registered plugin, and uses the Kafka Instance for worker coordination. |
| `automq_connector.orders` | Runs the Sink task with the topic, database connection, and write settings. |

The example also creates the `orders` topic and a `jdbc-reader` Kafka user.
Because the Instance uses SASL authentication, the Connector needs that user's
credentials and permission to consume the topic. A topic CONSUME ACL and a
GROUP ACL for `connect-${local.connector_name}` provide the required access.
Worker-level Kafka authentication is managed by AutoMQ.

The desired write behavior determines the Connector settings:

| Data flow choice | Terraform configuration |
| --- | --- |
| Read order events | Set `connector_config.topics` to the created `orders` topic. |
| Write to the prepared PostgreSQL table | Set `connection.url`, `connection.user`, and `collection.name.format = "orders"`. Supply the password through `connector_config_sensitive`. |
| Update the row when an order is replayed | Set `insert.mode = "upsert"`, `primary.key.mode = "record_value"`, and `primary.key.fields = "order_id"`. |
| Keep table changes under database administration | Set `schema.evolution = "none"`. |
| Decode structured JSON records | Use `JsonConverter` with `value.converter.schemas.enable = "true"` in the Connect Cluster's `worker_config`. |
| Start with a small worker deployment | Set provisioned capacity to one `TIER1` worker and the Connector's `task_count` to `1`. |
| Authenticate against the Kafka Instance | Set the Connector's security protocol to `SASL_PLAINTEXT` with `SCRAM-SHA-512` and the `jdbc-reader` credentials. |

The Connect Cluster references the plugin's name and version, and the Connector
references the Connect Cluster ID. These references establish the creation
order. The Connector also depends on both Kafka ACLs so that access is granted
before the task starts.

### Supply the Environment Details

The Kafka Instance and AKS infrastructure already exist. Two additional
dependencies are needed: the JDBC plugin archive and a PostgreSQL database
reachable from the Connect workers.

Host a compatible Debezium JDBC plugin ZIP, including the PostgreSQL JDBC
driver, at an HTTPS URL accessible to the Console and Connect runtime. See the
[Debezium JDBC documentation](https://debezium.io/documentation/reference/3.2/connectors/jdbc.html)
for packaging and configuration requirements.

In PostgreSQL, create the table that matches the order record:

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

Then fill in the `locals` block in [connector/main.tf](connector/main.tf):

| Local value | Information to provide |
| --- | --- |
| `environment_id`, `kafka_instance_id` | The same BYOC Environment ID and the `instance_id` output from the previous example. |
| `kubernetes_cluster_id`, `node_pool_name` | The AKS cluster full ARM ID and node pool with capacity for the Connect worker. |
| `connect_namespace`, `connect_service_account` | The namespace and Kubernetes ServiceAccount for the worker deployment. |
| `plugin_storage_url`, `plugin_version` | The reachable Debezium JDBC archive URL and its matching version. |
| `connector_name` | The name of this data flow; the group ACL derives its default consumer group from this value. |
| `kafka_password` | A password for the Kafka user created by this example. Both the user and Connector reference this value. |
| `jdbc_url`, `database_username`, `database_password` | Connection details for the prepared PostgreSQL database and authorized user. |

Use a namespace and ServiceAccount supported by your Connect configuration.
If the runtime requires Azure Workload Identity, prepare the worker identity,
federation, and grants according to the target version's documentation, including
`compute.iam_role` where required.

The AutoMQ Service Account authorizes Terraform API calls, the Kafka user
authorizes topic consumption, and the PostgreSQL user authorizes database
writes. Keep these credentials separate. Sensitive Terraform fields hide
passwords from normal output, but the values remain in state.

### Create and Verify the Data Flow

From `instance/`, initialize the Connector configuration and review the plan.
It should create the topic, user, two ACLs, plugin registration, Connect Cluster,
and Connector. Apply the plan after checking the target environment and inputs:

```bash
cd ../connector
terraform init
terraform plan
terraform apply
terraform output connector_state
```

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

Send another record with the same `order_id` and a different `amount`, then
query the table again. The existing row should contain the new amount. This
checks the upsert behavior chosen at the start of the example.

For other task, authentication, and lifecycle options, see the
[Connector resource documentation](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/connector).

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
