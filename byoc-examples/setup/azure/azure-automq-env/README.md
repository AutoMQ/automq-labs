# AutoMQ on Azure with Terraform (AKS + Console)

This configuration creates the Azure stack for AutoMQ on AKS using existing network and storage resources:
- Creates a resource group for AKS/console resources, and uses existing VNet and public/private subnets provided by the user (network module exists but is not invoked here).
- AKS cluster (system node pool only).
- AutoMQ user node pool with dedicated taint.
- AutoMQ console VM using existing operations/data storage accounts and containers.
- User-assigned identities and role assignments.

## Prerequisites
- Terraform >= 1.3
- Azure CLI logged in (`az login`)
- Existing VNet + public/private subnets, and existing storage accounts and containers for ops/data buckets.
- Custom image ID for the AutoMQ console VM.
- AKS agent pool name must be 1-12 lowercase letters/numbers (default: "automq").

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
- Network profile: Azure CNI/policy, LB Standard, outbound via load balancer; service CIDR and DNS service IP are configurable (defaults 10.2.0.0/16 and 10.2.0.10) to avoid overlap with VNet/subnets.
- Kubeconfig: written locally to `kubeconfig_path` (default `~/.kube/automq-aks-config`), not output in plaintext.

## Quick start
1. Prepare `terraform.tfvars`:
```hcl
subscription_id           = "<subscription-guid>"
resource_group_name       = "<existing-rg>"
location                  = "eastus"
vnet_id                   = "/subscriptions/.../virtualNetworks/<vnet>"
public_subnet_id          = "/subscriptions/.../subnets/<public>"
private_subnet_id         = "/subscriptions/.../subnets/<private>"
ops_storage_account_name  = "opsaccount"
ops_storage_resource_group = "ops-rg"
ops_container_name        = "opscontainer"
data_storage_account_name = "dataaccount"
data_storage_resource_group = "data-rg"
data_container_name       = "datacontainer"
automq_console_id         = "/subscriptions/218357d0-eaaf-4e3e-9ffa-6b4ccb7e2df9/resourceGroups/automq-image/providers/Microsoft.Compute/images/AutoMQ-control-center-Prod-7.8.7-x86_64"
automq_console_vm_size    = "Standard_D2s_v3"
nodepool = {
  name       = "automq"
  vm_size    = "Standard_D4as_v5"
  min_count  = 1
  max_count  = 5
  node_count = 2
  spot       = false
}
kubeconfig_path = "~/.kube/automq-aks-config"
```

2. Init/plan/apply:
```bash
terraform init
terraform plan
terraform apply
```

## Outputs
- `kubeconfig_path`: local path where kubeconfig is written.
- `automq_nodepool_name`: created user node pool.
- `automq_console_endpoint`, `automq_console_username`, `automq_console_password`.
- Network and resource group identifiers.
