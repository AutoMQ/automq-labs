# AutoMQ 8.x on Azure with Terraform

This evaluation quick-start deploys an AutoMQ BYOC 8.x Console and an AKS
foundation into an existing Azure VNet. The Console runs as a Docker container
on a standard Ubuntu VM; it no longer uses the legacy AutoMQ Community Gallery
VM image.

## What This Creates

- A Resource Group in `location`, which must match the Azure region encoded in
  AutoMQ `CONFIG`.
- An AKS cluster with Microsoft Entra integration, Azure RBAC, OIDC issuer, and
  Azure Workload Identity enabled.
- A dedicated three-zone AutoMQ node pool with the
  `dedicated=automq:NoSchedule` taint and `automq-node-group=automq` label.
- An Ubuntu Console VM with a separate persistent data disk.
- The AutoMQ 8.x Console container, initialized from the complete Base64
  `CONFIG` value supplied by AutoMQ Cloud.
- Separate Console and Data Plane user-assigned managed identities.
- The Ops Storage Account and Container named by
  `CONFIG.opsBucket.bucketName`.
- A Terraform-provided data container and Private DNS Zone that can be used as
  customer-provided Instance resources.

This example grants broad subscription-level Console permissions so the 8.x
System Initialization flow can exercise managed resources. It is intended for
evaluation, not as a production IAM baseline.

## Prerequisites

- Terraform 1.3 or later.
- Azure credentials allowed to create the resources and role assignments in
  this example.
- An existing VNet with separate Console and AKS subnets.
- An AutoMQ Cloud Azure BYOC environment.
- The complete `CONFIG` value and exact Azure Console 8.x image from the same
  installation command.
- The Storage Account name in `CONFIG` must still be available in Azure.

The AKS subnet should have at least 512 addresses. The Kubernetes service CIDR
must not overlap the VNet or either subnet.

## Deploy

1. Copy the example variables:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. In `terraform.tfvars`, set:

   - `automq_config` to the entire value after `CONFIG=`. Do not decode or
     edit it.
   - `console_image` to the exact image shown in the same installation
     command.
   - The Azure subscription, matching region, Resource Group, VNet, subnet,
     service CIDR, and existing `env_prefix` inputs.

3. Deploy:

   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. Get the Console login:

   ```bash
   terraform output -raw automq_console_endpoint
   terraform output -raw automq_console_username
   terraform output -raw automq_console_password
   ```

The VM becoming `Running` does not mean the Console is ready. Wait for the
login page to respond. On the first login, reset the generated bootstrap
password when prompted, then finish **System Initialization**.

## Create an AutoMQ Instance

In the Console, create a K8S Instance using:

- Cluster: `kubernetes_cluster_id`
- Node pool: `automq_nodepool_name`
- Load balancer subnet: `private_subnet_id`
- Scheduling taint: `dedicated=automq:NoSchedule`
- Scheduling label: `automq-node-group=<automq_nodepool_name>`

The `data_bucket_id`, `dns_zone_id`, and `workload_identity_id` outputs are
customer-provided Instance resources. Using the UAMI also requires the
matching Kubernetes ServiceAccount and Federated Identity Credential.

## Important Outputs

| Output | Meaning |
| --- | --- |
| `automq_console_endpoint` | AutoMQ Console URL |
| `automq_console_password` | One-time initial admin password |
| `console_initial_access_key` / `console_initial_secret_key` | Initial local Console API credentials |
| `kubernetes_cluster_id` | AKS full ARM ID |
| `automq_nodepool_name` | Dedicated AutoMQ node pool |
| `ops_bucket_id` | Azure logical Ops Bucket ID in `account:container` form |
| `data_bucket_id` | Terraform-provided logical Data Bucket ID |
| `dns_zone_id` | Terraform-provided Private DNS Zone full ARM ID |
| `workload_identity_id` | Terraform-provided Data Plane UAMI full ARM ID |

## Console Runtime

The bootstrap script:

- installs Docker on Ubuntu 22.04;
- formats and mounts the separate disk at `/data`;
- stores the Console environment in `/etc/automq-console.env` with mode
  `0600`;
- runs the container with `/data:/root`, host networking, restart policy, and
  bounded Docker logs.

For diagnostics, SSH to the VM and inspect:

```bash
sudo tail -n 200 /var/log/cloud-init-output.log
sudo docker logs --tail 200 automq-console
```

## Security and State

- The original example interface keeps ports 22 and 8080 open. Restrict the
  Network Security Group before using it outside a disposable environment.
- The Console endpoint is plain HTTP on port 8080. Add HTTPS and a controlled
  ingress layer for durable use.
- Terraform state contains `CONFIG`, the initial password, API credentials,
  and the generated SSH private key. Use an encrypted remote backend with
  restricted access.
- The included subscription-level `Contributor` and
  `Role Based Access Control Administrator` assignments are deliberately
  broad. Replace them with the reviewed 8.x System Initialization permission
  contract before production use.

## Cleanup

Delete AutoMQ Instances from the Console first, then run:

```bash
terraform destroy
```

Destroying this quick-start removes the Console disk and the Terraform-managed
Ops/Data containers. Preserve any required data before cleanup.
