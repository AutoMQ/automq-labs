---
last_updated: 2026-11-26
---

# AutoMQ Connect with Debezium MySQL on GKE

Create one AutoMQ Connect Cluster on an existing GKE cluster. The example
creates the namespace, Kubernetes and Google service accounts, Workload
Identity binding, Ops Bucket permissions, and Console-to-worker firewall rule.
It uses one `TIER1` worker and the fixed `debezium-mysql:3.1.2` system plugin.

Only `kubernetes_cluster_id` is required when using the companion Console and
Kafka deployments. MySQL CDC is optional and disabled by default.

## Before you start

- Complete the [Console](../terraform/) and [Kafka Instance](../automq-cluster/)
  deployments and retain their local Terraform states.
- Use GKE Standard in the Console's project, Region, and VPC, with Workload
  Identity enabled. The default `default-pool` must use `GKE_METADATA`, have
  spare capacity for a worker, and have no scheduling taints.
- Confirm that `debezium-mysql:3.1.2` is `ACTIVE` in the Console plugin catalog.
  This example pins AutoMQ Provider `0.4.10` and uses the Console 8.4.13 contract.
- Install Terraform 1.7 or later (before 2.0), Google Cloud CLI, and `kubectl`.
  Sign in to the CLI with `gcloud auth login` if needed. The Console and GKE
  API must be reachable from your machine.

For IAM permissions, custom node pools, or an existing Console state, see
[advanced configuration and troubleshooting](./ADVANCED.md).

## Create the Connect Cluster

Run from the repository root:

```bash
cd byoc-examples/setup/gcp/automq-connect
```

### 1. Prepare Terraform authentication

Terraform uses Application Default Credentials (ADC), separately from your
CLI sign-in. Install the GKE credential plugin and add its SDK directory to
`PATH`:

```bash
gcloud auth application-default login
gcloud components install gke-gcloud-auth-plugin
export PATH="$(gcloud info --format='value(installation.sdk_root)')/bin:$PATH"
gke-gcloud-auth-plugin --version
```

If your SDK uses a system package manager, follow Google's
[plugin installation instructions](https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_plugin).
Terraform obtains fresh credentials through the plugin; it does not need a
local kubeconfig.

### 2. Fill in the GKE ID

Create a local parameter file without overwriting an existing one:

```bash
cp -n terraform.tfvars.example terraform.tfvars
```

Set this one required value in `terraform.tfvars`:

```hcl
kubernetes_cluster_id = "projects/your-project/locations/us-central1/clusters/your-gke"
```

If you used the companion GKE setup, get the ID with:

```bash
terraform -chdir=../../kubernetes/gcp/terraform output -raw gke_cluster_id
```

Console credentials, environment ID, and Ops Bucket name are read from
`../terraform/terraform.tfstate`. The Kafka Instance ID comes from
`../automq-cluster/terraform/terraform.tfstate`. No credentials need copying.

### 3. Review and apply

```bash
terraform init
terraform plan -out=connect.tfplan
terraform apply connect.tfplan
```

Review the selected GKE cluster and node pool, namespace, worker identity,
bucket permissions, and firewall rule before applying. Terraform creates the
supporting resources, then the Console deploys the Connect workers.

## Verify the workers

Run in the same terminal from this directory:

```bash
GKE_ID="$(terraform output -raw kubernetes_cluster_id)"
gcloud container clusters get-credentials "${GKE_ID##*/}" \
  --project="$(printf '%s' "$GKE_ID" | cut -d/ -f2)" \
  --location="$(printf '%s' "$GKE_ID" | cut -d/ -f4)"

CONNECT_NS="$(terraform output -raw connect_namespace)"
kubectl -n "$CONNECT_NS" get deployments,pods
terraform output connect_cluster_state
```

Expect the workers to be `Running` with all containers Ready. In the Console,
confirm that the Connect Cluster is ready and the installed plugin includes
`io.debezium.connector.mysql.MySqlConnector`. Terraform outputs reflect the
last state refresh; use the Pods and Console to check current runtime status.

## Optional: capture a MySQL table

Prepare a MySQL source reachable from the workers, with TLS, binlogging, and
CDC permissions. See [source requirements](./ADVANCED.md#mysql-source-requirements).
This example uses an existing database; it does not create MySQL.

Uncomment and fill in the optional block in your local `terraform.tfvars`:

```hcl
create_mysql_connector = true
mysql_hostname         = "mysql.internal.example"
mysql_user             = "debezium"
mysql_password         = "REPLACE_WITH_CDC_PASSWORD"
```

The defaults capture `inventory.customers` into
`mysql-cdc.inventory.customers`. If your source uses different names, also set
`mysql_database` and `mysql_table`. Keep credential-bearing local tfvars,
state, and saved plans out of Git; `terraform.tfvars` is ignored here.

```bash
terraform plan -out=mysql-cdc.tfplan
terraform apply mysql-cdc.tfplan
terraform output mysql_connector_state
terraform output -raw mysql_data_topic
```

Confirm that the Connector and its task are running in the Console, then
[consume the CDC Topic from GKE](./ADVANCED.md#consume-cdc-from-gke). Expect
`op = "r"` for the initial snapshot and `c`, `u`, or `d` for subsequent changes.

## Cleanup

Changing `create_mysql_connector` to `false` deletes the Connector and its data
Topic, including CDC records. It does not pause the Connector. The Connect
Cluster, source database, and Debezium schema history Topic remain.

To remove this example, review a destroy plan and apply it before removing the
Kafka Instance or Console:

```bash
terraform plan -destroy -out=destroy.tfplan
terraform apply destroy.tfplan
```

This removes the owned Connect resources, identities, namespace, firewall rule,
and optional Connector/data Topic. GKE, Console, Kafka Instance, Ops Bucket,
MySQL, and the schema history Topic remain. Use the namespace exclusively for
this example. See [resource ownership](./ADVANCED.md#resource-ownership).
