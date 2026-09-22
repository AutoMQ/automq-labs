# Manage AutoMQ Resources on Azure with Terraform

This optional example uses the `automq/automq` provider after the
[Azure BYOC environment setup](../README.md) and Console System Initialization
are complete. It contains two standalone Terraform roots with separate state:

- `instance/`: a three-zone, three-node Kafka Instance using S3WAL,
  usage-based pricing, and SASL_PLAINTEXT.
- `connector/`: a Datagen Source Connector that writes sample orders, including
  its plugin, Connect worker cluster, Kafka topic, user, and ACL.

These are evaluation examples. Adapt the configuration using the
[provider documentation](https://registry.terraform.io/providers/automq/automq/latest/docs).

## Prerequisites

- Terraform 1.3 or later. The examples pin AutoMQ provider 0.4.8.
- An initialized Azure BYOC environment with permission to create managed
  storage, identities, DNS resources, and Kubernetes workloads.
- An existing AKS cluster and AutoMQ node pool spanning three availability
  zones, with sufficient capacity and connectivity to the Console.
- A target Console/Data Plane version supporting Azure AKS, S3WAL, usage-based
  pricing, and, for the second example, Managed Connect.

The provider's published cloud support table does not yet specify an Azure
minimum Control Plane version. Confirm compatibility with your target
environment before applying. These examples have not been verified with a
live Azure deployment.

## Configure

### Create Service Account Credentials

Sign in to the AutoMQ Console, open **Service Accounts**, and create a Service
Account with permissions for the example resources. Create/download its Access
Key ID (AK) and Secret Access Key (SK). See
[Service Accounts](https://docs.automq.com/automq-cloud/manage-identities-and-access/service-accounts).

Get the environment's Control Plane endpoint and its `environment_id` from
**System Settings**. Export the endpoint and enter the credentials:

```bash
export AUTOMQ_BYOC_ENDPOINT="<console-endpoint>"
read -r -p 'AutoMQ Access Key ID: ' AUTOMQ_BYOC_ACCESS_KEY
read -r -s -p 'AutoMQ Secret Access Key: ' AUTOMQ_BYOC_SECRET_KEY
export AUTOMQ_BYOC_ACCESS_KEY AUTOMQ_BYOC_SECRET_KEY
```

Provider 0.4.8 reads `AUTOMQ_BYOC_ACCESS_KEY`, not
`AUTOMQ_BYOC_ACCESS_KEY_ID`. These credentials authenticate AutoMQ API calls;
they are separate from Azure credentials, installation `CONFIG`, and Kafka
SASL credentials. Keep credentials, Terraform state, and saved plans private.

### Configure the Kafka Instance

From this directory:

```bash
cd instance
cp terraform.tfvars.example terraform.tfvars
```

Replace the placeholders with values from the existing environment:

- Environment ID and a supported **Data Plane** version, not the Console version.
- AKS cluster and private load balancer subnet full ARM resource IDs.
- A supported instance type, node pool name, and three zone IDs returned by
  the Console for that node pool.

The scheduling settings match the environment example's `automq` node pool and
`dedicated=automq:NoSchedule` taint. Update them if your node pool differs.
Azure subnets are regional; workload zones come from the AKS node pool, so
`networks[].subnets` is empty and the load balancer subnet is configured separately.

| Setting | Value |
| --- | --- |
| Deployment | `K8S` on the existing AKS cluster |
| Pricing | `UsageBased` |
| AutoMQ nodes | `reserved_node_count = 3` |
| Placement | Three availability zones |
| WAL | `S3WAL`, backed by Azure Blob |
| Kafka security | `sasl` authentication with `plaintext` transport |

`data_buckets`, `instance_role`, and `dns_zone` are intentionally omitted.
The Control Plane creates and manages the Data Bucket, Data Plane UAMI, and
Private DNS Zone. Do not pass the environment setup's customer-provided bucket,
identity, or DNS outputs. AKS, networking, and the environment Ops Bucket remain
existing dependencies.

Three AutoMQ nodes are not the total AKS VM count. Allow capacity for system
pods and Connect workers. SASL_PLAINTEXT authenticates clients without transport
encryption; this example assumes private network access.

## Create

### Kafka Instance

Run in `instance/`:

```bash
terraform init
terraform validate
terraform plan -out=instance.tfplan
terraform apply instance.tfplan
terraform output -raw instance_id
terraform output endpoints
```

Confirm the Instance is ready in the Console and check its placement across
the selected availability zones.

### Datagen Connector

The second example registers a Datagen plugin, installs it into a one-worker
`TIER1` Connect Cluster, and creates a one-task Source Connector. It also creates
the three-partition `orders` topic and a `datagen-writer` Kafka user with PRODUCE
permission on that topic.

Before running it:

- Prepare a complete Datagen plugin ZIP compatible with the Connect runtime,
  with an HTTPS URL accessible to the Console/runtime. The plugin resource
  registers an archive; it does not build or upload it. See the
  [Datagen documentation](https://github.com/confluentinc/kafka-connect-datagen).
- Confirm the namespace, ServiceAccount, scheduling capacity, and networking
  required by your Console's Connect implementation. If runtime access requires
  Azure Workload Identity, configure the worker UAMI, federation, and grants
  according to that version's documentation, including `compute.iam_role` when
  required. The Kafka Instance identity is not automatically the worker identity.

From `instance/`:

```bash
cd ../connector
cp terraform.tfvars.example terraform.tfvars
# Fill in the Instance ID from the previous step and all other placeholders.
read -r -s -p 'Kafka datagen-writer password: ' TF_VAR_kafka_password
export TF_VAR_kafka_password
terraform init
terraform validate
terraform plan -out=connector.tfplan
terraform apply connector.tfplan
```

The Connector uses `SASL_PLAINTEXT` with `SCRAM-SHA-512` for its producer.
AutoMQ manages worker-level Kafka authentication. Plugin settings belong in
`connector_config`; `connector.class` and `tasks.max` are injected from
`connector_class` and `task_count`.

The example disables producer idempotence to demonstrate topic-level write
permissions. Adjust reliability settings and ACLs for your use case. For a
database Source or Blob Sink, replace the plugin and its configuration and
provide the external system's permissions and credentials. Use
`connector_config_sensitive` for sensitive plugin settings.

## Outputs

Run in `connector/`:

```bash
terraform output connect_cluster_id
terraform output connector_id
terraform output connector_state
```

Check Connect Cluster/task health and incoming `orders` records or write metrics
in the Console. Client-side consumption requires a separate user with topic
CONSUME and consumer group permissions; the example writer has write access only.

For later changes, review `terraform plan` before applying, particularly resource
replacements. Follow each resource's import documentation to adopt existing resources.

## Cleanup

Destroy Connector resources before the Kafka Instance:

```bash
# From connector/
terraform destroy
cd ../instance
terraform destroy
```

The roots have separate state and pass the Instance ID manually; Terraform does
not enforce this cross-state cleanup order. Clean up environment infrastructure
last, and check the target version's data retention behavior before deleting it.

## Reference

- [Provider](https://registry.terraform.io/providers/automq/automq/0.4.8/docs)
- [Kafka Instance](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/kafka_instance)
- [Kafka Topic](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/kafka_topic),
  [Kafka User](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/kafka_user),
  [Kafka ACL](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/kafka_acl)
- [Connector Plugin](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/connector_plugin)
- [Connect Cluster](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/connect_cluster)
- [Connector](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/connector)
