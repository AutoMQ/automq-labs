# Deploy AutoMQ BYOC Console on Azure with Terraform

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
  `dedicated=automq:NoSchedule` taint.
- An Ubuntu Console VM with a separate persistent data disk.
- The AutoMQ 8.x Console container, initialized from the complete Base64
  `CONFIG` value supplied by AutoMQ Cloud.
- Separate Console and Data Plane user-assigned managed identities.
- The Ops Storage Account and Container named by
  `CONFIG.opsBucket.bucketName`.
- A Terraform-provided data container and Private DNS Zone that can be used as
  customer-provided Instance resources.

This example follows the Azure playground V1 permission contract: Console and
workload identities use explicit custom roles, with runtime assignments scoped
to the selected containers, Private DNS Zone, AKS cluster, Resource Group, and
AKS node Resource Group.

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
   - Optionally set `kubernetes_namespace` and
     `kubernetes_service_account` together to create the AKS OIDC Federated
     Identity Credential for the workload UAMI.

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

For a step-by-step Terraform walkthrough after System Initialization, see
[automq-example](automq-example/README.md): create Service Account credentials,
provision a managed Azure Kafka Instance, and add a Debezium JDBC Sink for PostgreSQL.

In the Console, create a K8S Instance using:

- Cluster: `kubernetes_cluster_id`
- VNet: `vnet_id`
- Node pool: `automq_nodepool_name`
- Scheduling taint: `dedicated=automq:NoSchedule`

The `data_bucket_id`, `dns_zone_id`, and `workload_identity_id` outputs are
customer-provided Instance resources. When the Kubernetes namespace and
ServiceAccount inputs are omitted, create the matching Federated Identity
Credential before using the workload UAMI.

## Identity Permissions

The Console UAMI receives the customer-provided and managed-resource custom
roles from the Azure playground contract:

- container-scoped Blob data access;
- zone-scoped DNS record access;
- cluster-scoped AKS read and `clusterUser` credential access;
- Resource Group-scoped managed Storage, Private DNS, and UAMI lifecycle
  access;
- subscription-scoped discovery reads and conditional RBAC delegation.

This example enables Microsoft Entra integration and Azure RBAC for Kubernetes
Authorization on the AKS cluster. Grant the Console UAMI
`Azure Kubernetes Service RBAC Cluster Admin` at the target cluster scope as
part of System Initialization. The AKS access role used to obtain the
`clusterUser` kubeconfig does not grant Kubernetes management permissions by
itself.

The workload UAMI receives only Blob runtime access on the Ops/Data
containers, DNS record access on the selected zone, and disk failover actions
on the AKS node Resource Group. When configured, its Federated Identity
Credential uses the AKS OIDC issuer and the supplied Kubernetes ServiceAccount
subject.

## Important Outputs

| Output | Meaning |
| --- | --- |
| `automq_console_endpoint` | AutoMQ Console URL |
| `automq_console_password` | One-time initial admin password |
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
- Terraform state contains `CONFIG`, the initial password, and the generated
  SSH private key. Use an encrypted remote backend with restricted access.
- Custom role definitions are registered at subscription scope, while runtime
  role assignments use the narrower scopes described above. Review the
  actions and ABAC conditions against your production policy before use.

## Cleanup

Delete AutoMQ Instances from the Console first, then run:

```bash
terraform destroy
```

Destroying this quick-start removes the Console disk and the Terraform-managed
Ops/Data containers. Preserve any required data before cleanup.
