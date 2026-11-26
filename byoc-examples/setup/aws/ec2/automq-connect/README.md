---
last_updated: 2026-11-26
---

# AutoMQ Connect on an existing EKS cluster

Create one `TIER1` Connect worker on an existing EKS cluster, using the AutoMQ
Cluster from `../automq-cluster`. Terraform creates a dedicated namespace,
ServiceAccount, and worker IAM role, and configures Console access to EKS,
worker REST, and built-in Prometheus metrics. The Console and Kafka brokers
run on EC2; Connect workers run on EKS.

The default deployment starts the Connect Cluster without a Connector or MySQL
dependency. You can enable [MySQL CDC](#optional-mysql-cdc) in the same root and
state. Running workers and CDC storage/traffic consume billable resources.

## Before you start

For the companion EC2 examples, use this deployment order:

**Console and VPC → AutoMQ Cluster + EKS in the same VPC → Connect Cluster**

The following environments must be ready before applying this example. After
the Console and VPC are ready, the AutoMQ Cluster and EKS can be prepared
independently:

| Prerequisite | Required state | Setup and preparation |
| --- | --- | --- |
| AutoMQ BYOC Console (CMP Console) | Initialized and reachable, running on EC2 in the target AWS account and Region. The companion setup also creates the VPC. | [Console and VPC](../README.md#quick-start) |
| AutoMQ Cluster | Running on EC2 in the same AutoMQ environment as the Console and reachable from Connect workers. | [AutoMQ Cluster setup](../README.md#quick-start) |
| Kubernetes environment (Amazon EKS) | An existing cluster and worker nodes in the Console's AWS account, Region, and VPC, with capacity for Connect workers. | [EKS preparation](#eks-preparation) |

Keep the local Terraform states for both the Console and AutoMQ Cluster;
this example reads their connection details and resource IDs automatically.
Supply the existing EKS cluster name through `kubernetes_cluster_id`.

Also check the following:

- Terraform `>= 1.7.0, < 2.0.0` and AWS CLI on the Terraform machine.
- Your Console must support the Connect APIs used by AutoMQ Terraform Provider
  `0.4.10`; the adjacent example's default `8.3.16-aws` image is not a
  compatibility guarantee.
- An existing EKS cluster in the Console's AWS account, Region, and VPC, with
  private API access, authentication mode `API` or `API_AND_CONFIG_MAP`, an
  [associated IAM OIDC provider](#eks-preparation), and capacity for one `TIER1`
  worker. The Terraform identity must already have Kubernetes permission to
  create a namespace and its ServiceAccount. An AWS login alone does not grant it.
- The Terraform machine can reach both the Console and Kubernetes APIs. Workers
  can reach each other, the Kafka private endpoints, and their image/plugin
  downloads. Terraform configures Console ingress to EKS and worker REST/metrics;
  [other network paths](#network-access) remain external prerequisites.
- An `ACTIVE` plugin in **Kafka Connect > Plugins**. The default name is
  `mysql-debezium-cdc`; use its exact available version. This root does not
  register plugins. If you use managed `debezium-mysql`, set `plugin_name` and
  `plugin_version` from your running Console's catalog. See
  [Manage Plugins](https://docs.automq.com/automq-cloud/kafka-connect/manage-plugins).

An existing MySQL source is required only when enabling the optional MySQL
Connector. Prepare its network access, binlogging, TLS, and CDC account as
described in [MySQL CDC](#optional-mysql-cdc).

## Quick start

From this directory:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Replace the two required values:

```hcl
kubernetes_cluster_id = "my-existing-eks-cluster"
plugin_version        = "REPLACE_WITH_ACTIVE_PLUGIN_VERSION"
```

For AWS, `kubernetes_cluster_id` means the **EKS cluster name**, not its ARN.
The Region and API credentials come from the adjacent Console state; the AutoMQ
Cluster ID comes from the adjacent Cluster state. No `CONFIG` or API key copy is
needed. Use your normal AWS credential chain, including `AWS_PROFILE`, or set
`aws_profile`. Both AWS and Kubernetes authentication use that profile;
Terraform calls `aws eks get-token` without requiring a kubeconfig.

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### Verify the Cluster

```bash
terraform output -raw connect_cluster_id
terraform output -raw connect_cluster_state
```

In **Kafka Connect > Connect Clusters**, confirm the Cluster and its workers
are running and the selected plugin is installed. The default deployment does
not produce CDC messages. To capture a table, continue below.

## Optional MySQL CDC

Enabling CDC in this root creates one Debezium MySQL Connector and one
single-partition data Topic. It captures exactly one `mysql_database.mysql_table`
with an initial snapshot followed by ongoing changes. The installed plugin must
provide `io.debezium.connector.mysql.MySqlConnector`.

Prepare an existing MySQL source before enabling it:

- Workers must resolve its hostname and reach its port, normally `3306`.
  Configure security groups, routes, DNS, and any cross-VPC connectivity first.
  This root does not create MySQL or its network paths.
- Enable `log_bin=ON`, `binlog_format=ROW`, and `binlog_row_image=FULL`;
  avoid `PARTIAL_JSON` in `binlog_row_value_options`. Retain binlogs long enough
  for snapshots and recovery.
- Give the CDC user `SELECT`, `SHOW DATABASES`, `RELOAD`, `REPLICATION SLAVE`, and
  `REPLICATION CLIENT` as supported by the service. RDS/Aurora snapshot locking
  also needs `LOCK TABLES`. For RDS for MySQL, prepare automated backups,
  parameter groups, and binlog retention. Follow the
  [Debezium MySQL setup guide](https://debezium.io/documentation/reference/3.1/connectors/mysql.html#setting-up-mysql).
- Choose a `mysql_server_id` unique among this topology's replication clients
  and servers. The default is `184054`. The default `mysql_ssl_mode = "required"`
  requires TLS; it encrypts traffic without verifying server identity.
- Keep the AutoMQ Cluster's private plaintext listener enabled. This root reads
  one unambiguous VPC/private `PLAINTEXT` bootstrap value from the Kafka state.
  It uses anonymous Kafka access without ACL credentials. Debezium's history
  clients need native Kafka Create/Describe/Read/Write access.

For a dedicated test database `inventory` that your DBA has already created,
prepare a demonstration table using a DDL/application-write account. Skip this
SQL if capturing an existing table; do not run it against a production source.

```sql
CREATE TABLE inventory.customers (
  id INT PRIMARY KEY,
  name VARCHAR(100) NOT NULL
);
INSERT INTO inventory.customers (id, name) VALUES (1, 'snapshot-row');
```

Add the connection settings to your local `terraform.tfvars`:

```hcl
create_mysql_connector = true
mysql_hostname         = "mysql.internal.example"
mysql_user             = "your-cdc-user"
mysql_password         = "your-cdc-password"
```

The three connection values are required only when CDC is enabled. The default
table is `inventory.customers`; set `mysql_database` and `mysql_table` to change
it. Names accept letters, numbers, and underscores, not regexes or table lists.
Your local tfvars, state, and saved plans contain the password; do not commit them.

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

This may be the first apply or an update to an existing Connect Cluster.
Inspect `mysql_connector_id`, `mysql_connector_state`, and `mysql_data_topic`
outputs, then confirm the Connector and its task are running in the Console.
From a client with private Kafka access, consume the default data Topic:

```bash
kafka-console-consumer.sh \
  --bootstrap-server '<private-plaintext-bootstrap-hosts>' \
  --topic mysql-cdc.inventory.customers \
  --from-beginning \
  --property print.key=true \
  --timeout-ms 30000
```

Expect a Debezium JSON envelope with `op = "r"` for the seed row. After the
snapshot completes, test changes using an application-write account:

```sql
SET autocommit = 1;
INSERT INTO inventory.customers (id, name) VALUES (2, 'cdc-insert');
UPDATE inventory.customers SET name = 'cdc-update' WHERE id = 2;
DELETE FROM inventory.customers WHERE id = 2;
```

Expect `c`, `u`, and `d` events with `before`/`after` fields and no `payload`
wrapper. A delete can also produce a null tombstone; retries or prior runs can
add records, so do not expect an exact count.

### Topic ownership

Terraform owns the data Topic, named `<topic_prefix>.<mysql_database>.<mysql_table>`
(`mysql-cdc.inventory.customers` by default). Choose an unused prefix. If the
Topic exists, change the name or explicitly transfer sole ownership before
importing it; do not manage the same Topic from multiple states.

Debezium creates its own dedicated history Topic, `schema-history.<connector_name>`
(`schema-history.mysql-cdc-demo` by default). In Debezium `3.1.2`, it requests one
partition, `cleanup.policy=delete`, `retention.ms=9223372036854775807`
(`Long.MAX_VALUE`), and `retention.bytes=-1`; see the
[pinned implementation](https://github.com/debezium/debezium/blob/v3.1.2.Final/debezium-storage/debezium-storage-kafka/src/main/java/io/debezium/storage/kafka/history/KafkaSchemaHistory.java#L479).
An existing history Topic is not automatically repaired: verify its settings,
keep it exclusive to this Connector, and preserve it for recovery.
`mysql_schema_history_topic` reports the configured name, not a Terraform
resource or proof of creation. All four MySQL outputs are `null` when CDC is disabled.

## Cleanup

Changing `create_mysql_connector` from `true` to `false` deletes the Connector
and its data Topic, including CDC records. It is a removal operation, not a
pause. The source database and Debezium-created history Topic remain.

To remove the whole Connect example:

```bash
terraform destroy
```

Terraform removes the optional Connector and data Topic, Connect Cluster,
dedicated namespace/ServiceAccount, worker role and policy attachments, added
Console EKS authorization, and its Console ingress rules. Namespace deletion
also removes anything else placed inside it. The existing EKS cluster, shared
OIDC provider, security groups, attached managed-policy documents, plugin,
Console role/instance profile, AutoMQ Cluster, and MySQL remain under their
original owners. Revoking Console-to-EKS access can affect other workloads
that rely on those same grants.

Keep EKS and its OIDC provider available until destroy completes. Destroy roots
in order: `automq-connect` → `automq-cluster` → `automq-console`.
Delete history manually only when retiring the capture and discarding its
recovery state; do not delete or expire it while retaining Connector offsets
for a later resume.

## Advanced configuration

Defaults are intended for a dedicated evaluation deployment. Override them only
when your environment requires it; choose unused namespace and ServiceAccount
names. Import existing objects only when this root will become their sole owner.

| Inputs | Default / use |
| --- | --- |
| `aws_region` / `aws_profile` | Region from Console state / normal AWS credential chain; an explicit Region must match the state |
| `console_state_path` / `kafka_state_path` | `../automq-console/terraform.tfstate` / `../automq-cluster/terraform.tfstate` |
| `connect_namespace` / `connect_service_account` | `automq-connect` / `automq-connect`; created and owned here |
| `connect_cluster_name` | `aws-mysql-connect-demo` |
| `plugin_name` / `connect_version` | `mysql-debezium-cdc` / Console's default worker version |
| `worker_count` / `worker_resource_spec` | `1` / `TIER1`; existing EKS capacity required |
| `kubernetes_scheduling_spec` | `null`; optional YAML with node selectors and tolerations |
| `connect_worker_role_name` | `null`; generate a unique IAM role name |
| `connect_plugin_s3_prefix` | `automq/connect-plugins`; no wildcards or edge slashes |
| `connect_worker_policy_arns` | `[]`; additional existing managed policies for other S3 locations, SSE-KMS, or other AWS services |
| `connect_worker_security_group_ids` | `[]`; use the EKS primary SG, or specify actual worker node/Pod SGs for both REST and metrics ingress |
| `console_eks_access_wait_duration` | `60s`; propagation buffer after grant/rule changes; accepts `2m` or `0s`, unchanged applies do not wait |
| `console_endpoint_override` | `null`; a reachable Console API URL, for example `http://127.0.0.1:18080` with a maintained SSM tunnel |
| `connector_name` / `topic_prefix` | `mysql-cdc-demo` / `mysql-cdc` |
| `mysql_port` / `mysql_server_id` / `mysql_ssl_mode` | `3306` / `184054` (must be unique) / `required` |
| `mysql_database` / `mysql_table` | `inventory` / `customers` |
| `tags` | `{ purpose = "evaluation" }` |

The Console state supplies `environment_id`, `region`, `ops_bucket_name`,
`console_role_arn`, `console_security_group_id`, `console_endpoint`, and initial
API key outputs. State, Region, account, and network checks run before deployment.
An SSM endpoint override changes only the AutoMQ Provider URL; keep the session
open. It does not tunnel Kubernetes/worker traffic or change the Home endpoint.

### Authorization

The three identities have separate responsibilities:

| Identity | Access |
| --- | --- |
| Terraform AWS identity | EKS/OIDC/SG reads; worker IAM lifecycle; Console inline-policy and EKS access-entry/association management; ingress-rule lifecycle; its own Kubernetes namespace/ServiceAccount access |
| Existing Console EC2 role | Added read-only EKS discovery policy and cluster-scoped `AmazonEKSClusterAdminPolicy` through a `STANDARD` access entry |
| New worker IRSA role | Trusts only the created ServiceAccount; reads plugin packages under the configured Ops-bucket prefix with prefix-scoped `ListBucket` |

Console discovery covers clusters in the current account and Region; detailed
node-group and access-entry reads target the selected cluster. No AWS EKS write
permissions are added to the Console. Its Kubernetes access is cluster-admin,
matching CMP's current check, rather than namespace-scoped. This example targets
the commercial `aws` partition.

The Terraform identity needs `iam:PutRolePolicy`, `iam:GetRolePolicy`, and
`iam:DeleteRolePolicy` on the existing Console role, EKS access-entry and policy
association management/read/tag rights, and worker IAM role/policy management.
For ingress it needs `ec2:DescribeSecurityGroups`, `ec2:DescribeSecurityGroupRules`,
`ec2:AuthorizeSecurityGroupIngress`, `ec2:ModifySecurityGroupRules`,
`ec2:RevokeSecurityGroupIngress`, `ec2:CreateTags`, and `ec2:DeleteTags`.
These EC2 rights belong to the Terraform identity, not the Console runtime role.
The Console grant does not authorize the local Terraform identity in Kubernetes.

This root owns the added Console inline policy, access entry, and association;
it retains the original Console role/profile ownership. Resolve any existing
grant's ownership before applying, importing only for sole ownership here.

### Network access

Terraform adds TCP `443` ingress on the EKS primary SG, plus TCP `8083` for REST
and TCP `9090` for built-in Prometheus metrics on the worker SGs. All rules use
the Console SG as their source. Standard EKS managed nodes with ordinary VPC CNI
use the primary SG by default: no SG input is needed. For custom node/Pod SGs,
`connect_worker_security_group_ids` overrides both REST and metrics ingress.
Destroy revokes only this root's rules: three by default, or `1 + 2N` for `N` worker SGs.

Console egress stays unchanged; the adjacent example allows all outbound traffic.
Routes, peering, DNS, NACLs, NetworkPolicy, worker-to-Kafka access, and MySQL
`3306` access remain external. The wait after IAM/SG changes buffers propagation;
it does not prove runtime readiness.

### EKS preparation

This root reads the existing EKS endpoint, CA, and shared IAM OIDC provider;
it does not create EKS, node groups, or the OIDC provider, or change EKS API/auth settings.
If OIDC is missing, an EKS administrator can associate it separately:

```bash
AWS_PROFILE='<your-eks-admin-profile>' eksctl utils associate-iam-oidc-provider \
  --cluster '<existing-eks-cluster-name>' --region '<aws-region>' --approve
```

### Troubleshooting and compatibility

- For EKS/Kubernetes failures, check the Terraform identity's own access,
  private API reachability, auth mode, OIDC, and scheduling capacity. For worker
  startup, check image/plugin downloads and private Kafka connectivity. IAM/SG
  outputs identify the configured resources for diagnosis.
- For missing CPU/Memory, check Console-to-Pod TCP `9090` access; the remote-write
  switch does not control built-in collection, which does not use metrics-server.
- On first-apply `DescribeCluster` `AccessDenied`, confirm the Console policy and
  principal. If the same running principal subsequently succeeds, allow
  propagation, then generate a fresh plan and apply. No EC2 or EKS rebuild is needed.
- The Console Topic API limits `retention.ms` to one hour–60 days; `-1` returns
  HTTP 400. History therefore uses Debezium's native Kafka creation, not that
  API or a shortened retention period. Check history settings if it already exists.
- For CDC failures, check task logs, MySQL network/TLS, privileges, binlogs,
  snapshot progress, and private Kafka access.

Provider `0.4.10` can report `Provider produced inconsistent result after apply`
if explicitly configured default `key.converter`/`value.converter` classes are
filtered from Console reads. This example omits those defaults and sets only
the non-default schema options. To recover an earlier affected deployment,
first confirm the Cluster is healthy and its ID exists in state, remove those
two default keys, then run:

```bash
terraform untaint automq_connect_cluster.demo
terraform plan
```

Confirm the fresh plan does not replace the running Cluster before applying.
Validation covers Terraform checks and mocked contract tests; it does not prove
your Console API/plugin compatibility, EKS/network access, or live CDC success.
