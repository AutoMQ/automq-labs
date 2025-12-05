# AutoMQ on Azure with Terraform (AKS + Console)

This configuration creates the Azure stack for AutoMQ on AKS:
- Creates a resource group for all resources.
- Uses an existing VNet and public/private subnets provided by the user.
- Creates an AKS cluster (system node pool only).
- Creates an AutoMQ user node pool with a dedicated taint.
- Creates a new storage account and containers for ops/data buckets.
- Deploys an AutoMQ console VM.
- Creates user-assigned identities and role assignments.

## Prerequisites
- Terraform >= 1.3
- Azure CLI logged in (`az login`)
- Existing VNet with public and private subnets.
- Custom image ID for the AutoMQ console VM (optional, has a default).

## Directory layout
```
azure-automq-env/
  main.tf            # root wiring modules
  variables.tf
  modules/
    aks/
    nodepool-automq/
    iam/
    automq-console/
```

Optional network bootstrap example (standalone): `byoc-examples/setup/azure/network-example`

## AKS configuration notes
- AKS control plane uses its own UAI created inside the AKS module; workload identity and OIDC issuer are enabled.
- System node pool: single node, auto-scaling enabled, `only_critical_addons_enabled = true`, temporary name for rotation (default `tmp`).
- User node pool `automq`: taint `dedicated=automq:NoSchedule`, supports spot/regular, subnet from input, UAI assigned to VMSS post-creation.
- Nodepool VMSS identity: the module automatically invokes `modules/nodepool-automq/attach_vmss_identity.sh` to bind the provided `cluster_identity_id` to the VMSS corresponding to the node pool. This script can also be run standalone:
  ```bash
  bash modules/nodepool-automq/attach_vmss_identity.sh \
    <AKS_CLUSTER_ID> <NODEPOOL_NAME> <UAI_ID>
  ```
- Network profile: Azure CNI/policy, LB Standard, outbound via load balancer; service CIDR and DNS service IP are configurable (defaults 10.2.0.0/16 and 10.2.0.10) to avoid overlap with VNet/subnets.
- Kubeconfig: written locally to `kubeconfig_path` (default `~/.kube/automq-aks-config`), not output in plaintext.
- Console SSH key: written to `~/.ssh/automq-console-ssh-key.pem` by Terraform.

## Quick start
1. Prepare `terraform.tfvars`:
```hcl
subscription_id     = "<subscription-guid>"
resource_group_name = "<existing-rg>"
location            = "eastus"
env_prefix          = "automq"

# Existing network resources
vnet_id           = "/subscriptions/.../virtualNetworks/<vnet>"
public_subnet_id  = "/subscriptions/.../subnets/<public>"
private_subnet_id = "/subscriptions/.../subnets/<private>"

# AKS service CIDR and DNS service IP
service_cidr   = "10.2.0.0/16"
dns_service_ip = "10.2.0.10"

# Optional variables with default values
# kubernetes_version      = "1.32.9"
# kubernetes_pricing_tier = "Free"
# kubeconfig_path         = "~/.kube/automq-aks-config"
# automq_console_id       = "/subscriptions/218357d0-eaaf-4e3e-9ffa-6b4ccb7e2df9/resourceGroups/automq-image/providers/Microsoft.Compute/images/AutoMQ-control-center-Prod-7.8.7-x86_64"
# automq_console_vm_size  = "Standard_D2s_v3"
# nodepool = {
#   name       = "automq"
#   vm_size    = "Standard_D4as_v5"
#   min_count  = 3
#   max_count  = 20
#   node_count = 3
#   spot       = false
# }
```

2. Init/plan/apply:
```bash
terraform init
terraform plan
terraform apply
```

## Outputs
- `resource_group_name`: Name of the resource group containing all resources.
- `aks_name`: Name of the created AKS cluster.
- `automq_nodepool_name`: Name of the AutoMQ user node pool.
- `automq_console_endpoint`: Public endpoint for the AutoMQ console.
- `automq_console_username`: Initial username for the AutoMQ console.
- `automq_console_password`: Initial password for the AutoMQ console (sensitive value).
- `dns_zone_name`: Name of the private DNS zone created for the console.
- `data_bucket_endpoint`: Endpoint for the data bucket.
- `nodepool_identity_client_id`: Client ID of the managed identity for the AutoMQ node pool.
- `storage_account_name`: Name of the storage account for AutoMQ buckets.
- `automq_data_bucket`: Name of the container for data.
- `automq_ops_bucket`: Name of the container for operations.
