---
last_updated: 2026-11-26
---

# AutoMQ Connect with Debezium MySQL on GKE

This Terraform example creates one AutoMQ Connect Cluster on an existing GKE
cluster and node pool. It installs the fixed system plugin
`debezium-mysql:3.1.2` for MySQL CDC demonstrations. The default capacity is one
`TIER1` worker.

The example has its own Terraform state. It creates:

- A dedicated Kubernetes namespace and Kubernetes ServiceAccount (KSA).
- A Google Service Account (GSA), a precise KSA-to-GSA Workload Identity binding,
  and `roles/storage.objectUser` on the environment's existing Ops Bucket.
- An ingress firewall rule allowing the Console to reach Connect worker REST
  and metrics ports, TCP `8083` and `9090`, on the selected node pool's VM service
  account.
- The AutoMQ Connect Cluster, using the existing Kafka Instance.

It also enables the IAM Service Account Credentials API if necessary. The API
remains enabled when this example is destroyed.

The GKE cluster, node pool, Console, Kafka Instance, Ops Bucket, and system plugin
remain externally managed. This example does not create a MySQL database or a
Connector. Installing the plugin prepares the Connect Cluster for a later
MySQL Connector configuration.

## Prerequisites

- Terraform 1.7 or later, Google Cloud CLI, `kubectl`, and
  `gke-gcloud-auth-plugin` on `PATH`.
- Completed [Console](../terraform/) and [Kafka Instance](../automq-cluster/)
  deployments with their local Terraform state files available.
- This example pins AutoMQ Terraform Provider `0.4.10`. It uses the Connect API
  contract available in Console 8.4.13; deployment and runtime readiness must
  still be checked in the target environment.
- The system plugin `debezium-mysql`, version `3.1.2`, must be `ACTIVE` in the
  Console plugin catalog. Its connector class is
  `io.debezium.connector.mysql.MySqlConnector`. Plugin name and version are fixed
  in this example and are not input variables.
- GKE Standard in the same service project, Region, and VPC as the Console.
  Workload Identity must be enabled, and the selected node pool must use
  `GKE_METADATA` mode.
- Available CPU and memory in the selected node pool. The default is
  `default-pool`, keeping workers off the dedicated Broker pool. If the selected
  pool has taints, supply matching `connect_tolerations`.
- The Console's existing GSA must already be authorized to manage Kubernetes
  resources and reach the GKE API. The Console setup provides its
  `roles/container.admin` binding; this root does not duplicate that ownership
  or grant `cluster-admin` to workers.
- The Terraform caller must be authorized to read GKE and network metadata,
  create namespace/KSA/GSA resources, manage the relevant IAM bindings and
  firewall rule, and enable the required API.

The Console must be able to reach the selected workers' Pod IP addresses. The
workers need a network path to Kafka and outbound HTTPS for their container
images and plugin package. Private nodes normally use the existing Cloud NAT.
MySQL connectivity is needed only when a Connector is configured later.
The firewall targets the pool's VM service account. Other nodes in the same VPC
that share this identity receive the same REST/metrics ingress allowance.

## Authenticate

The Google and Kubernetes providers use local Application Default Credentials
(ADC):

```bash
gcloud auth application-default login
gcloud components install gke-gcloud-auth-plugin
```

For a Homebrew installation of Google Cloud CLI, the component binaries may
need this additional `PATH` entry in the current shell:

```bash
export PATH="$(brew --prefix)/share/google-cloud-sdk/bin:$PATH"
```

Check that the plugin is available:

```bash
gke-gcloud-auth-plugin --version
```

The Kubernetes provider invokes it with
`--use_application_default_credentials` to obtain fresh credentials during
Terraform operations; the example does not depend on a local kubeconfig.

AutoMQ API credentials, the endpoint, environment ID, and Ops Bucket name are
read from the existing Console state. The Kafka Instance ID is read from the
existing Instance state. Keep those local state files private because the
Console state contains bootstrap credentials.

### Local Provider overrides

If your global Terraform CLI configuration contains a local `dev_overrides`
entry for `automq/automq`, use a separate CLI configuration so this root uses
the pinned Registry release. From this directory, run:

```bash
cat > terraform.rc <<'EOF'
provider_installation {
  direct {}
}
EOF
export TF_CLI_CONFIG_FILE="$PWD/terraform.rc"
```

Keep this environment variable set in the same shell for `init`, `plan`, and
`apply`. It does not modify your global Terraform CLI configuration.

## Configure

Run the following commands from this directory:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Set `kubernetes_cluster_id` to the full external GKE resource name:

```hcl
kubernetes_cluster_id = "projects/your-project-id/locations/us-central1/clusters/your-gke-cluster"
```

This is the only required input when using the companion examples' state paths.
Terraform reads the cluster and pool metadata; it does not create or resize
either resource.

| Input | Purpose | Default |
| --- | --- | --- |
| `kubernetes_cluster_id` | Full external GKE resource name | Required |
| `connect_node_pool_name` | Existing pool used for worker scheduling | `default-pool` |
| `console_state_path` | Local Console state | `../terraform/terraform.tfstate` |
| `kafka_state_path` | Local Kafka Instance state | `../automq-cluster/terraform/terraform.tfstate` |
| `console_endpoint_override` | Optional Console endpoint reachable from this machine | `null` |
| `connect_cluster_name` | Connect Cluster display name | `gcp-mysql-connect-demo` |
| `connect_namespace` | Namespace owned exclusively by this example | `automq-connect` |
| `connect_service_account` | Worker KSA name | `automq-connect` |
| `worker_service_account_id` | Optional GSA account ID | Generated when `null` |
| `connect_tolerations` | Tolerations for the selected pool's taints | `[]` |
| `worker_count` | Provisioned worker count | `1` |
| `worker_resource_spec` | Provisioned worker resource tier | `TIER1` |
| `connect_version` | Connect worker version; `null` uses the Console default | `null` |
| `tags` | AutoMQ resource tags | Demo purpose tag |

The Connect worker version is separate from the Console image and Kafka Broker
version. If selecting it explicitly, use a version available in the Console's
Connect worker version list.

For an untainted node pool, leave `connect_tolerations` empty. Terraform omits
the `tolerations` field from the scheduling specification in that case, because
Console 8.4.13 rejects an explicitly empty list. Non-empty tolerations are sent
with the selected node pool's `nodeSelector`.

### Older Console state

The Connect root reads the environment Ops Bucket exclusively from the Console
state's `ops_bucket_name` output. If the Console was created before that output
was added, publish the output before planning Connect:

```bash
terraform -chdir=../terraform plan -refresh-only
terraform -chdir=../terraform apply -refresh-only
```

Use the current Console configuration, which includes the `ops_bucket_name`
output, and review the refresh plan before applying it. A refresh-only apply
updates local state and outputs without changing the remote Console resources.
If the output is still absent, the Connect preflight reports the missing Console
state output.

## Create

```bash
terraform init
terraform validate
terraform plan -out=connect.tfplan
```

Check the selected external GKE/pool, namespace, worker GSA, Ops Bucket access,
firewall rule, fixed plugin, and Connect capacity in the plan. Then apply the
saved plan:

```bash
terraform apply connect.tfplan
```

Google provider credentials create the supporting resources. The AutoMQ
provider calls the Console, which deploys and manages the Connect workers.
The namespace and KSA are created before that API request.

## Verify

```bash
terraform output -raw connect_cluster_id
terraform output connect_cluster_state
terraform output -raw worker_service_account_email
terraform output -raw console_to_workers_firewall
```

For Kubernetes inspection, configure your own `kubectl` context for the same
GKE cluster, then inspect the namespace returned by Terraform:

```bash
terraform output -raw kubernetes_cluster_id
kubectl -n "$(terraform output -raw connect_namespace)" get deployments,pods
kubectl -n "$(terraform output -raw connect_namespace)" get serviceaccount \
  "$(terraform output -raw connect_service_account)"
```

Confirm that the Connect Cluster is ready in the Console, workers are Ready,
and the installed plugin includes
`io.debezium.connector.mysql.MySqlConnector`. Connect uses the Ops Bucket for
telemetry; verify actual metrics/log delivery separately from Pod readiness.
CDC requires an independently configured MySQL source and Connector.

`terraform fmt`, `terraform validate`, and mock-provider tests check Terraform
structure and resource contracts. They do not prove worker startup, plugin
loading, GCP telemetry delivery, or MySQL CDC in a real deployment.

## Cleanup

Destroy this root before deleting its Kafka Instance or Console:

```bash
terraform plan -destroy
terraform destroy
```

This removes its Connect Cluster, dedicated namespace/KSA, worker GSA, IAM
bindings, and firewall rule. Use the namespace exclusively for this demo:
deleting it also deletes resources that were added to it outside Terraform.
The external GKE cluster, node pool, Console, Kafka Instance, Ops Bucket, and
system plugin are retained. The IAM Service Account Credentials API remains
enabled.
