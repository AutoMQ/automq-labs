---
last_updated: 2026-11-25
---

# AutoMQ Connect Cluster on an existing EKS cluster

Create a dedicated Kubernetes namespace, ServiceAccount, worker IAM role, and
AutoMQ Connect Cluster, and authorize the existing Console role to manage that
EKS cluster. The Cluster uses the Kafka
Instance from `../automq-cluster` and installs your registered
`mysql-debezium-cdc` plugin. The Console and Kafka brokers run on EC2; Connect
workers run on EKS.

By default, `create_mysql_connector = false` creates the Cluster infrastructure
without starting CDC. A MySQL server, database credentials, and MySQL network
access are not required in that mode. To capture one table, enable
[optional MySQL CDC](#optional-mysql-cdc) in this same root and apply; Terraform
also creates the Connector and its CDC data Topic. Debezium creates its own
schema history Topic when it starts. Terraform-managed Connect resources share
one state.

Terraform does not create MySQL or change network connectivity. The existing
EKS cluster, shared IAM OIDC provider, plugin, Console, and Kafka Instance retain
their original ownership. Running workers and CDC storage/traffic consume
billable resources.

## Prerequisites

- Terraform `1.7.0` or later, below `2.0.0`, and AWS CLI available on the machine
  running Terraform.
- Apply `../automq-console` and `../automq-cluster` first. Complete Console
  initialization and wait for the Kafka Instance to be running.
- Use a Console release that supports the Connect Cluster API used by AutoMQ
  Terraform Provider `0.4.10`. The adjacent Console example's default image,
  `8.3.16-aws`, is not a compatibility guarantee for this API.
- Prepare an existing EKS cluster in the Kafka Instance's AWS account and
  Region. Set `aws_region` to that Region; its default is `us-east-1`, and it
  must match the Region exported by the Console state. For this
  quick start, use the same VPC as the Console and brokers. The Console must
  reach the Kubernetes API and worker Pod REST endpoints; workers must resolve
  Kafka private DNS names and reach the private Kafka listeners. The Terraform
  machine must also reach the Kubernetes API. Check routing, security groups,
  and network policies, including communication between Connect workers.
- EKS authentication mode must be `API` or `API_AND_CONFIG_MAP`, so that access
  entries can be used. This root checks the mode but does not change it.
- Ensure schedulable EKS node capacity for the worker tier. The default is one
  provisioned `TIER1` worker, without HPA or a Metrics Server requirement.
- Confirm that `mysql-debezium-cdc` is registered and `ACTIVE` in **Kafka
  Connect > Plugins**. Set `plugin_version` to its exact available version.
  This root does not register the plugin. If you intend to use managed
  `debezium-mysql` instead, select its name and version from your running
  Console's catalog. See
  [Manage Plugins](https://docs.automq.com/automq-cloud/kafka-connect/manage-plugins).
- Workers need outbound access to download their images and plugin package.
  Terraform needs access to the Console API, its neighboring state files, and
  the Terraform Registry.

Three identities have separate responsibilities:

| Identity | Required access |
| --- | --- |
| Your Terraform AWS identity | Read EKS/OIDC metadata; manage the worker role and policies, the Console's inline EKS policy, and its EKS access entry/association; create/delete the namespace and ServiceAccount through Kubernetes |
| Existing Console EC2 runtime IAM role | Receive an EKS read-only IAM policy and cluster-scoped Kubernetes administrator access to the target EKS cluster |
| New worker IRSA role | Trust only the created ServiceAccount through this EKS OIDC provider; read plugin packages under the configured prefix in the Console's Ops bucket |

An AWS login alone does not grant Kubernetes permissions. Your Terraform
identity must already have EKS access/RBAC for cluster-scoped namespace
creation and ServiceAccount management. Granting access to the Console role
does not grant access to the identity running Terraform.

The Terraform identity also needs `iam:PutRolePolicy`, `iam:GetRolePolicy`, and
`iam:DeleteRolePolicy` on the existing Console role, plus permission to manage
EKS access entries and policy associations, including their read and tag
operations. Worker role creation and policy management require the usual IAM
permissions for those resources.

### Console authorization managed by this root

Terraform reads the Console role ARN from the adjacent state and creates:

- An inline IAM policy for EKS discovery and read operations. Cluster discovery
  is limited to the configured Region and account; detailed node-group and
  access-entry reads are limited to the target cluster. The policy grants no
  EKS write operations to the Console.
- A `STANDARD` EKS access entry for that role, with EKS's default username.
- A cluster-scoped `AmazonEKSClusterAdminPolicy` association. This grants
  Kubernetes cluster administrator access; it is not a namespace-scoped
  permission set. It matches CMP's current access check.

This evaluation path targets the commercial `aws` partition. CMP's current
authorization check expects the `arn:aws` cluster-admin policy ARN.

The existing Console role, EC2 instance, and instance profile retain their
original ownership. This root owns the added inline policy, access entry, and
association. After creating or changing those grants, Terraform waits for
`console_eks_access_wait_duration` before creating the Connect Cluster. The
default `60s` buffers IAM/EKS permission propagation; it cannot guarantee that
every permission update has propagated. Use a longer value such as `2m` if
needed, or `0s` to disable the buffer. An unchanged apply does not repeat the
wait. This root does not configure VPC routing, peering, DNS, or security groups.

If the access entry, association, or inline policy already exists, resolve its
Terraform ownership before applying. Import it explicitly only when this root
will become its sole owner; do not manage the same authorization from multiple
states. Consider any other workloads using that Console-to-EKS authorization,
because destroying this root revokes the grants it manages.

### Existing IAM OIDC provider

The EKS cluster's OIDC issuer must already be registered as an IAM OIDC provider
in its AWS account. Terraform queries this shared provider to construct the
worker role's trust policy; it does not create or take ownership of it.

If the provider is missing, ask your EKS administrator to associate it first.
For example, using the intended AWS identity and Region:

```bash
AWS_PROFILE='<your-eks-admin-profile>' eksctl utils associate-iam-oidc-provider \
  --cluster '<existing-eks-cluster-name>' \
  --region '<aws-region>' \
  --approve
```

This is a separate, one-time EKS account preparation step, not part of this
root's lifecycle.

## Configure and deploy

From this directory:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Replace the EKS cluster name and plugin version, and select the AWS Region:

```hcl
kubernetes_cluster_id = "my-existing-eks-cluster"
aws_region            = "us-east-1"
plugin_name           = "mysql-debezium-cdc"
plugin_version        = "REPLACE_WITH_ACTIVE_PLUGIN_VERSION"
```

For AWS, `kubernetes_cluster_id` is the **EKS cluster name**, such as the value
passed to `aws eks update-kubeconfig --name`, not its ARN. Terraform reads the
cluster endpoint, CA, and OIDC issuer from AWS.

If you use a named AWS profile, set it consistently for both the AWS Provider
and Kubernetes authentication:

```hcl
aws_profile = "my-aws-profile"
```

Alternatively, leave `aws_profile` unset and use your normal AWS credential
chain, including `AWS_PROFILE`. The Kubernetes Provider calls
`aws eks get-token` with the same profile selection; a preconfigured kubeconfig
is not required.

Choose unused names for this example's dedicated Kubernetes objects:

```hcl
connect_namespace       = "automq-connect"
connect_service_account = "automq-connect"
```

This root creates and owns both objects. If an object with the same name
already exists, choose another name or explicitly import it only if you intend
to transfer its lifecycle to this root. Use a namespace dedicated to this
example: deleting it also removes resources placed inside it.

The neighboring local state paths default to:

```hcl
console_state_path = "../automq-console/terraform.tfstate"
kafka_state_path   = "../automq-cluster/terraform.tfstate"
```

The Console state supplies the environment, Region, Ops bucket name, Console
role ARN, and AutoMQ API credentials; the Kafka state supplies the Instance ID.
The Console state must export `region`, `ops_bucket_name`, and
`console_role_arn`. Terraform checks that `aws_region` matches that Region and
that its AWS identity belongs to the Console's account and partition. The role
ARN identifies the existing principal receiving the EKS authorization above;
this root does not create or replace that role or its EC2 instance profile.
Change the paths if the files are elsewhere. Do not copy API keys or `CONFIG`
into this root. Restrict access to state and plans, and do not commit them or
your tfvars file.

Review and apply:

```bash
terraform init
terraform plan
terraform apply
```

The main inputs are:

| Input | Default | Purpose |
| --- | --- | --- |
| `kubernetes_cluster_id` | Required | Existing EKS cluster name |
| `aws_region` | `us-east-1` | Region of that EKS cluster and Kafka Instance |
| `aws_profile` | `null` | Optional named AWS profile used by both providers |
| `plugin_name` | `mysql-debezium-cdc` | Existing registered plugin |
| `plugin_version` | Required | Exact ACTIVE version in your Console |
| `connect_namespace` | `automq-connect` | New dedicated Kubernetes namespace |
| `connect_service_account` | `automq-connect` | New ServiceAccount annotated with the created IRSA role |
| `connect_worker_role_name` | `null` | Optional explicit name; otherwise Terraform generates a unique role name |
| `connect_plugin_s3_prefix` | `automq/connect-plugins` | Plugin-package prefix in the Console's Ops bucket |
| `connect_worker_policy_arns` | `[]` | Additional existing managed policies to attach to the new worker role |
| `connect_cluster_name` | `aws-mysql-connect-demo` | New Connect Cluster name |
| `worker_count` / `worker_resource_spec` | `1` / `TIER1` | Fixed worker capacity |
| `connect_version` | `null` | Use the Console's default Connect worker version |
| `kubernetes_scheduling_spec` | `null` | Optional YAML matching existing node labels and taints |
| `console_endpoint_override` | `null` | Optional reachable Console API URL |
| `console_eks_access_wait_duration` | `60s` | Buffer after Console IAM/EKS authorization changes; for example `2m` or `0s` |

The new worker role trusts only this namespace and ServiceAccount. Its inline
policy grants `s3:GetObject` for plugin packages under the configured prefix
in the Console's Ops bucket, plus `s3:ListBucket` restricted to that prefix.
Set `connect_plugin_s3_prefix` to match a customized CMP package prefix; do not
include wildcards or leading/trailing slashes. Packages in other S3 locations
or encrypted with SSE-KMS need additional permissions on the corresponding
resources through `connect_worker_policy_arns`. Other AWS service access also
uses that optional policy list. Terraform manages the attachments, not the
existing policy documents themselves. For dedicated or tainted
nodes, supply a scheduling spec matching existing labels and tolerations;
this root does not create node groups.

### Optional: Console access through an SSM tunnel

If you maintain an AWS Systems Manager port-forwarding session from local port
`18080` to the Console EC2 instance's port `8080`, set:

```hcl
console_endpoint_override = "http://127.0.0.1:18080"
```

Keep the session open while Terraform accesses the API. AutoMQ authentication
still comes from the Console state. The override changes only the AutoMQ
Provider's API URL; it does not tunnel Kubernetes or worker traffic or change
the Console's Home endpoint.

## Verify the Connect Cluster

Inspect the outputs:

```bash
terraform output -raw eks_cluster_name
terraform output -raw connect_namespace
terraform output -raw connect_service_account
terraform output -raw connect_iam_role_arn
terraform output -raw console_role_arn
terraform output -raw console_eks_access_entry_arn
terraform output -raw connect_cluster_id
terraform output -raw connect_cluster_state
```

Confirm the Cluster is running in **Kafka Connect > Connect Clusters**, inspect
its workers, and check that the selected plugin is installed. With
`create_mysql_connector = false`, no CDC messages are expected. To start a
capture task, configure the optional MySQL settings below.

If Terraform fails while reading EKS or creating Kubernetes objects, check its
AWS identity, Kubernetes access, API endpoint reachability, authentication
mode, and existing OIDC provider. Access-entry failures can also indicate
insufficient EKS management permissions or an existing grant owned elsewhere.
For later worker failures, check Console authorization, node scheduling,
image/plugin downloads, and private Kafka
connectivity. A reachable Console login page alone does not establish these
prerequisites.

If the first apply reports `DescribeCluster` `AccessDenied`, confirm that the
Console's policy and EKS authorization are correct. If a subsequent check from
the running Console under the same principal succeeds, allow propagation time,
then generate a fresh plan and apply again:

```bash
terraform plan
terraform apply
```

An authorization propagation delay does not require rebuilding the Console
EC2 instance or the EKS cluster.

### Worker defaults and Provider 0.4.10

The Console omits worker settings that match the selected version's defaults
when returning the configuration. With Provider `0.4.10`, explicitly setting
the default `key.converter` and `value.converter` classes can therefore cause
`Provider produced inconsistent result after apply`, even after the Cluster
is running. This example relies on the default converter classes and sets
only the non-default schema options.

If an earlier apply encountered this error, first confirm that the Cluster is
healthy and its ID is present in Terraform state. Remove the two default
converter keys from `worker_config`, then clear the taint on that existing
resource and generate a fresh plan:

```bash
terraform untaint automq_connect_cluster.demo
terraform plan
```

Confirm that the plan does not replace the running Cluster before proceeding.

## Optional MySQL CDC

Set `create_mysql_connector = true` to add a Debezium MySQL Connector and its
CDC data Topic in the same Terraform apply. The installed plugin must provide
`io.debezium.connector.mysql.MySqlConnector`, and your Console must support the
Connector API used by Provider `0.4.10`. This root captures one
`mysql_database.mysql_table`; these two name inputs accept letters, numbers,
and underscores, not regexes or table lists.

Prepare the source before enabling capture:

- Use an existing supported MySQL database and table. Workers must resolve the
  hostname and reach its port, normally `3306`. Configure routes, DNS, security
  groups, and network policies first, including cross-VPC connectivity for RDS
  if needed. Terraform does not provision the database or network paths.
- Enable binlogging with `log_bin=ON`, `binlog_format=ROW`, and
  `binlog_row_image=FULL`. Avoid `PARTIAL_JSON` in `binlog_row_value_options`
  and retain binlogs long enough for snapshots and recovery.
- Give the CDC user `SELECT`, `SHOW DATABASES`, `RELOAD`, `REPLICATION SLAVE`,
  and `REPLICATION CLIENT` permissions as supported by the service.
  RDS/Aurora snapshot locking also needs `LOCK TABLES`. RDS for MySQL requires
  automated backups for binlogging; its parameter group and binlog retention
  must be prepared by the database owner. See the
  [Debezium MySQL setup guide](https://debezium.io/documentation/reference/3.1/connectors/mysql.html#setting-up-mysql).
- Choose a unique `mysql_server_id` for this replication topology. The default
  `184054` must be changed if it is already used by another server or client.
- Keep the target Kafka Instance's private plaintext listener enabled. This
  root automatically selects one distinct VPC/private `PLAINTEXT` bootstrap
  value from the existing Kafka state, rejecting public-only or ambiguous
  selections. CDC output and schema history use this same Kafka Instance.
  Debezium's native Kafka clients need Create/Describe/Read/Write access for
  their history Topic. This example uses anonymous `PLAINTEXT` without Kafka
  ACL credentials; Console API credentials are separate.

For a dedicated test database named `inventory` that your DBA has already
created, you can prepare the demonstration table using a DDL/application-write
account before applying. Do not run this SQL against a production source:

```sql
CREATE TABLE inventory.customers (
  id INT PRIMARY KEY,
  name VARCHAR(100) NOT NULL
);
INSERT INTO inventory.customers (id, name) VALUES (1, 'snapshot-row');
```

If using an existing table instead, set its database and table names and skip
that SQL. Terraform does not execute database setup or grant MySQL privileges.
The CDC account needs read/replication access, not application-write access.

Add these settings to your existing `terraform.tfvars`:

```hcl
create_mysql_connector = true
mysql_hostname         = "mysql.internal.example"
mysql_user             = "your-cdc-user"
mysql_password         = "your-cdc-password"
```

`mysql_hostname`, `mysql_user`, and `mysql_password` default to `null`; all three
must be provided in your local `terraform.tfvars` when capture is enabled;
replace the example placeholders with your database connection values.
Your local tfvars, state, and saved plans contain the password; do not commit them.

| MySQL input | Default | Purpose |
| --- | --- | --- |
| `create_mysql_connector` | `false` | Create/manage the optional Connector and its CDC data Topic |
| `mysql_hostname` / `mysql_user` / `mysql_password` | `null` | Required when capture is enabled |
| `mysql_port` | `3306` | MySQL port reachable from workers |
| `mysql_database` / `mysql_table` | `inventory` / `customers` | One existing table to capture |
| `mysql_server_id` | `184054` | Unique replication-client ID |
| `mysql_ssl_mode` | `required` | Encrypt MySQL traffic; this setting alone does not verify server identity |
| `connector_name` | `mysql-cdc-demo` | Unique Connector name |
| `topic_prefix` | `mysql-cdc` | Data Topic prefix |

The default data Topic is `mysql-cdc.inventory.customers`, with one partition.
Terraform creates and deletes it. Choose an unused `topic_prefix`; if that data
Topic already exists, change the name or transfer its ownership explicitly
before import. Do not manage the same data Topic from multiple states.

Debezium creates the dedicated history Topic `schema-history.mysql-cdc-demo`
through its native Kafka Admin client at startup. Debezium `3.1.2` requests
one partition, `cleanup.policy=delete`,
`retention.ms=9223372036854775807` (`Long.MAX_VALUE`), and
`retention.bytes=-1`, preserving the DDL history for recovery. See the
[pinned Debezium history implementation](https://github.com/debezium/debezium/blob/v3.1.2.Final/debezium-storage/debezium-storage-kafka/src/main/java/io/debezium/storage/kafka/history/KafkaSchemaHistory.java#L479).

The Console Topic API accepts `retention.ms` only from one hour to 60 days;
creating history through that API with `-1` returns HTTP 400. This example
therefore leaves history creation to Debezium's native Kafka API rather than
substituting a short retention period. If the history Topic already exists,
verify its partition count and retention settings; Debezium does not repair
an existing Topic's settings automatically. Use an exclusive history name and
do not share it across Connectors.

Review and apply from this same directory:

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

This can be your first apply or an update to the existing Connect deployment;
there is no additional Connect state to manage. The MySQL preconditions are
checked when capture is enabled. Its outputs are then available:

```bash
terraform output -raw mysql_connector_id
terraform output -raw mysql_connector_state
terraform output -raw mysql_data_topic
terraform output -raw mysql_schema_history_topic
```

These outputs are `null` while `create_mysql_connector` is `false`.
`mysql_schema_history_topic` reports the configured history name, not a
Terraform-managed resource or proof that startup has created it. Confirm the
Connector and task are running in the Console, then consume the data Topic
from a client with private Kafka access:

```bash
kafka-console-consumer.sh \
  --bootstrap-server '<private-plaintext-bootstrap-hosts>' \
  --topic mysql-cdc.inventory.customers \
  --from-beginning \
  --property print.key=true \
  --timeout-ms 30000
```

The initial snapshot emits `op = "r"` for the seed row. After it completes, use
an application-write account to test the demonstration table:

```sql
SET autocommit = 1;
INSERT INTO inventory.customers (id, name) VALUES (2, 'cdc-insert');
UPDATE inventory.customers SET name = 'cdc-update' WHERE id = 2;
DELETE FROM inventory.customers WHERE id = 2;
```

Expect Debezium JSON envelopes with `op` values `c`, `u`, and `d` and matching
`before`/`after` fields. With this example's JSON converter settings, there is
no `payload` wrapper. A delete can also emit a null-valued tombstone; retries
or prior runs can add records, so do not assume an exact count. If capture
fails, check task logs, MySQL TLS support, permissions, binlog configuration,
snapshot progress, and worker-to-database/Kafka connectivity. The default
`required` SSL mode needs database TLS support.

Changing `create_mysql_connector` from `true` to `false` schedules deletion of
the Connector and its CDC data Topic, including its records. The Debezium-created
history Topic remains. Use that change only when you intend to remove the
Terraform-managed capture resources.

## Cleanup

Keep EKS and its IAM OIDC provider available until this root has been destroyed.
Destroy this root before the Kafka Instance or Console. Terraform's dependencies
remove the optional Connector before its CDC data Topic and Connect Cluster:

```bash
terraform destroy
```

If enabled, Terraform deletes the MySQL Connector and its CDC data Topic,
including the stored CDC records. The source MySQL database and table remain.
The schema history Topic is outside Terraform's lifecycle and is retained;
delete it manually only when you deliberately retire the capture and discard
its recovery state. Do not delete or expire history while preserving the
Connector or offsets for a later resume.

Terraform also deletes the Connect Cluster, dedicated namespace,
ServiceAccount, worker IAM role, its inline plugin-download policy, and its
managed-policy attachments. It also deletes the Console's added inline EKS
policy, access entry, and cluster-admin association, revoking this root's Console-to-EKS
authorization. The existing Console role and EC2 instance profile remain.
AutoMQ removes the worker
deployment. Confirm cleanup completes before dismantling the surrounding
environment. Existing EKS infrastructure, its shared IAM OIDC provider, the
policy documents attached by ARN, plugin, Kafka Instance, and Console remain
under their original owners.

For the complete example, destroy roots in this order:
`automq-connect` → `automq-cluster` → `automq-console`.

## Validation scope

Validation includes Terraform validation and mocked contract tests. The MySQL
CDC path has not been exercised against a live database. Local checks do not
prove Console API compatibility, plugin availability, EKS permissions,
networking, or successful worker and Connector startup.
