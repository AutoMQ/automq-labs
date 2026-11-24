---
last_updated: 2026-11-24
---

# AutoMQ Connect Cluster on an existing EKS cluster

Create a dedicated Kubernetes namespace, ServiceAccount, worker IAM role, and
AutoMQ Connect Cluster, and authorize the existing Console role to manage that
EKS cluster. The Cluster uses the Kafka
Instance from `../automq-cluster` and installs your registered
`mysql-debezium-cdc` plugin. The Console and Kafka brokers run on EC2; Connect
workers run on EKS.

This stage does not create a Connector or start CDC. A MySQL server, database
credentials, and MySQL network access are not required yet. Terraform does not
create or delete the EKS cluster, its shared IAM OIDC provider, the plugin,
Console, or Kafka Instance. Running workers consume billable resources.

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
its workers, and check that the selected plugin is installed. No database
changes or CDC messages are expected because no Connector has been created.

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

## Cleanup

Keep EKS and its IAM OIDC provider available until this root has been destroyed.
Destroy it before destroying the Kafka Instance or Console:

```bash
terraform destroy
```

Terraform deletes the Connect Cluster, dedicated namespace, ServiceAccount,
worker IAM role, its inline plugin-download policy, and its managed-policy
attachments. It also deletes the Console's added inline EKS policy, access
entry, and cluster-admin association, revoking this root's Console-to-EKS
authorization. The existing Console role and EC2 instance profile remain.
AutoMQ removes the worker
deployment. Confirm cleanup completes before dismantling the surrounding
environment. Existing EKS infrastructure, its shared IAM OIDC provider, the
policy documents attached by ARN, plugin, Kafka Instance, and Console remain
under their original owners.

For the complete example, destroy roots in this order:
`automq-connect` → `automq-cluster` → `automq-console`.

## Validation scope

Validation is limited to Terraform validation and mocked contract tests. This
example has not been verified by creating a live Connect deployment. Local
checks do not prove Console API compatibility, plugin availability, EKS
permissions, networking, or successful worker startup.
