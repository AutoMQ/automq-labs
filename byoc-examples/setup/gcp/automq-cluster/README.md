# Create an AutoMQ Instance on GCP

This optional Terraform example uses the `automq/automq` provider to create one
AutoMQ Instance after the GKE and Console setups are ready. It is a standalone
reference with its own Terraform state and is not called by either setup.

The example creates:

- A GKE Standard deployment across three zones.
- Three usage-based AutoMQ nodes.
- S3WAL object-storage-backed WAL.
- Control Plane-managed Data Bucket, DNS Zone, and Instance Identity.
- Anonymous plaintext access inside the VPC.

It reuses the dedicated AutoMQ node pool from the GKE setup through its
`node_type=automq` label and `dedicated=automq:NoSchedule` taint. It does not
create another node pool.

## Prerequisites

- AutoMQ Control Plane 8.3.8 or later.
- Terraform 1.3 or later.
- A completed [GKE setup](../../kubernetes/gcp/terraform/).
- A completed [Console setup](../terraform/).

## Configure

Get the GKE values:

```bash
terraform output -raw gke_cluster_id
terraform output -raw workload_subnet_id
terraform output -json zones
```

Get the Console values:

```bash
terraform output -raw console_endpoint
terraform output -raw console_initial_access_key
terraform output -raw console_initial_secret_key
terraform output -raw automq_environment_id
```

Protect the Console credentials and Terraform state. Both contain sensitive
values.

Edit the example values in `terraform/main.tf`, then export the Console
credentials:

```bash
export AUTOMQ_BYOC_ENDPOINT="<console-endpoint>"
export AUTOMQ_BYOC_ACCESS_KEY="<console-access-key>"
export AUTOMQ_BYOC_SECRET_KEY="<console-secret-key>"
```

## Create

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

The managed resources are intentionally omitted from `compute_specs`. The
Control Plane creates and manages the Instance Data Bucket, DNS Zone, and cloud
identity.

## Outputs

```bash
terraform output -raw instance_id
terraform output instance_status
terraform output -json instance_endpoints
```

## Cleanup

```bash
terraform destroy
```
