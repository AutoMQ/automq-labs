# Add an AutoMQ Node Pool to an Existing AKS Cluster

This Terraform configuration adds a dedicated AutoMQ node pool to an existing Azure Kubernetes Service (AKS) cluster and attaches the AutoMQ workload identity to the VMSS backing that node pool.

The `workload_identity_id` value must be the Resource ID of an Azure User Assigned Managed Identity, not its Client ID. Azure VMSS user-assigned identity attachment requires the full Managed Identity Resource ID.

## Prerequisites

Install the following tools locally:

- Terraform >= 1.3
- Azure CLI

The Azure account running Terraform must have permissions to:

- Read the target AKS cluster.
- Create a node pool in the target AKS cluster.
- Read the target AKS node resource group.
- Patch the identity of the VMSS backing the AKS node pool.
- Read or create the User Assigned Managed Identity used by AutoMQ.

Log in to Azure:

```bash
az login
```

If your account has access to multiple subscriptions, switch to the subscription that was used to create the existing AKS cluster:

```bash
az account set --subscription "<subscription-id>"
```

## Required Parameters

Environment parameters such as `subscription_id`, `aks_name`, `aks_resource_group_name`, and `subnet_id` must reuse the values from the original AKS installation. If you do not have the original installation parameters, you can check them from the AKS cluster page in Azure Portal or query them with Azure CLI.

The Terraform variables file needs the following core values:

```hcl
subscription_id         = "<subscription-guid>"
aks_name                = "<existing-aks-name>"
aks_resource_group_name = "<existing-aks-resource-group>"

nodepool_name        = "automq"
workload_identity_id = "/subscriptions/<subscription-guid>/resourceGroups/<identity-rg>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<identity-name>"

subnet_id  = "/subscriptions/<subscription-guid>/resourceGroups/<network-rg>/providers/Microsoft.Network/virtualNetworks/<vnet-name>/subnets/<subnet-name>"
vm_size    = "Standard_D4as_v5"
node_count = 3
min_count  = 3
max_count  = 20
spot       = false

tags = {
  app         = "automq"
  component   = "nodepool"
  environment = "prod"
  cost_center = "platform"
}
```

If your organization uses custom tags for cost allocation, chargeback, or FinOps reporting, set the `tags` parameter before creating the node pool. These tags are applied to the AutoMQ AKS node pool resources.

## 1. Confirm subscription_id

`subscription_id` must be the same subscription used by the existing AKS cluster. You can copy it from the original AKS installation configuration, or open the AKS cluster in Azure Portal and check the Subscription field on the Overview page.

To check the current Azure CLI subscription:

```bash
az account show --query id -o tsv
```

After confirming that the current subscription is the one containing the target AKS cluster, set:

```hcl
subscription_id = "<subscription-id>"
```

To list all available subscriptions:

```bash
az account list --query "[].{name:name,id:id,isDefault:isDefault}" -o table
```

## 2. Confirm aks_name and aks_resource_group_name

`aks_name` and `aks_resource_group_name` must refer to the existing AKS cluster created during the previous AKS installation. Reuse the original cluster name and resource group name.

If you are not sure which values were used, list AKS clusters in the current subscription:

```bash
az aks list --query "[].{name:name,resourceGroup:resourceGroup,location:location,kubernetesVersion:kubernetesVersion}" -o table
```

Set the values for the target AKS cluster:

```hcl
aks_name                = "<AKS cluster name>"
aks_resource_group_name = "<AKS resource group>"
```

You can also open the existing AKS cluster in Azure Portal and check the Overview page:

- Name
- Resource group

## 3. Get workload_identity_id

The AutoMQ node pool needs an Azure User Assigned Managed Identity attached to its backing VMSS. This identity is usually created during the AutoMQ environment initialization process and is used by AutoMQ workloads to access Azure resources such as object storage and networking resources.

Use the full Managed Identity Resource ID. Do not use the Client ID.

If you know the Managed Identity name and resource group, run:

```bash
az identity show \
  --name "<identity-name>" \
  --resource-group "<identity-resource-group>" \
  --query id \
  -o tsv
```

The output should look like this:

```text
/subscriptions/218357d0-eaaf-4e3e-9ffa-6b4ccb7e2df9/resourcegroups/rg-yifei-0615/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uai-workload-yifei0615-o8iv
```

Use the full output as:

```hcl
workload_identity_id = "/subscriptions/.../resourceGroups/.../providers/Microsoft.ManagedIdentity/userAssignedIdentities/..."
```

If you know the resource group but not the identity name, list User Assigned Managed Identities in that resource group:

```bash
az identity list \
  --resource-group "<identity-resource-group>" \
  --query "[].{name:name,id:id,clientId:clientId}" \
  -o table
```

If you do not know the resource group, list all User Assigned Managed Identities in the current subscription:

```bash
az identity list --query "[].{name:name,resourceGroup:resourceGroup,id:id,clientId:clientId}" -o table
```

Azure Portal path:

1. Open Azure Portal.
2. Search for `Managed Identities`.
3. Select the User Assigned Managed Identity used by AutoMQ.
4. Open the identity and copy the `Resource ID` from `JSON View` on the Overview page, or from Properties.

## 4. Get subnet_id

The new node pool must join an existing subnet. In most cases, reuse the node subnet from the original AKS installation so that networking, routing, and security group settings remain consistent with the existing cluster.

If you know the VNet and subnet names, run:

```bash
az network vnet subnet show \
  --resource-group "<network-resource-group>" \
  --vnet-name "<vnet-name>" \
  --name "<subnet-name>" \
  --query id \
  -o tsv
```

Set the output as:

```hcl
subnet_id = "/subscriptions/.../resourceGroups/.../providers/Microsoft.Network/virtualNetworks/.../subnets/..."
```

If you are not sure about the VNet and subnet names, list VNets first:

```bash
az network vnet list --query "[].{name:name,resourceGroup:resourceGroup,location:location}" -o table
```

Then list subnets in the selected VNet:

```bash
az network vnet subnet list \
  --resource-group "<network-resource-group>" \
  --vnet-name "<vnet-name>" \
  --query "[].{name:name,addressPrefix:addressPrefix,id:id}" \
  -o table
```

## 5. Set Node Pool Parameters

### nodepool_name

The AutoMQ node pool name is user-defined:

```hcl
nodepool_name = "automq"
```

AKS node pool naming requirements:

- 1-12 characters
- Lowercase letters and numbers only

### vm_size

Keep the default VM size unless you have a specific capacity plan:

```hcl
vm_size = "Standard_D4as_v5"
```

If you need to change it, list available VM sizes in the AKS region:

```bash
az vm list-sizes --location "<aks-region>" -o table
```

To get the AKS region:

```bash
az aks show \
  --name "<aks-name>" \
  --resource-group "<aks-resource-group>" \
  --query location \
  -o tsv
```

### node_count, min_count, max_count

Keep the default node counts unless you have a specific capacity plan. Autoscaling is enabled by default:

```hcl
node_count = 3
min_count  = 3
max_count  = 20
```

Meaning:

- `node_count`: initial node count
- `min_count`: minimum node count for autoscaling
- `max_count`: maximum node count for autoscaling

### spot

Whether to use Spot nodes:

```hcl
spot = false
```

For production environments, keep `spot = false` unless you explicitly accept Spot eviction risk.

### tags

Set custom tags before creating the node pool if your organization needs cost allocation, chargeback, ownership tracking, or FinOps reporting.

Example:

```hcl
tags = {
  app          = "automq"
  component    = "nodepool"
  environment  = "prod"
  owner        = "platform-team"
  cost_center  = "cc-12345"
  business_unit = "data-platform"
}
```

These tags are applied to the AutoMQ AKS node pool resources.

## 6. Create terraform.tfvars

Enter this directory:

```bash
cd existing-aks-automq-nodepool
```

Copy the example variables file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and fill in the values collected above. Example:

```hcl
subscription_id         = "218357d0-eaaf-4e3e-9ffa-6b4ccb7e2df9"
aks_name                = "aks-yifei-0615"
aks_resource_group_name = "rg-yifei-0615"

nodepool_name        = "automq"
workload_identity_id = "/subscriptions/218357d0-eaaf-4e3e-9ffa-6b4ccb7e2df9/resourcegroups/rg-yifei-0615/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uai-workload-yifei0615-o8iv"

subnet_id  = "/subscriptions/218357d0-eaaf-4e3e-9ffa-6b4ccb7e2df9/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-automq/subnets/snet-private"
vm_size    = "Standard_D4as_v5"
node_count = 3
min_count  = 3
max_count  = 20
spot       = false

tags = {
  app          = "automq"
  component    = "nodepool"
  environment  = "prod"
  cost_center  = "cc-12345"
  business_unit = "data-platform"
}
```

## 7. Run Terraform

Initialize Terraform:

```bash
terraform init
```

Review the plan:

```bash
terraform plan
```

Confirm that the plan creates a new AKS node pool and patches the VMSS identity behind that node pool. Then apply:

```bash
terraform apply
```

Wait until Terraform finishes and the node pool is created successfully. After that, open the AutoMQ console and create an AutoMQ cluster.

## 8. Verify the Result

List AKS node pools:

```bash
az aks nodepool list \
  --cluster-name "<aks-name>" \
  --resource-group "<aks-resource-group>" \
  --query "[].{name:name,vmSize:vmSize,count:count,mode:mode,provisioningState:provisioningState}" \
  -o table
```

Get the AKS node resource group:

```bash
az aks show \
  --name "<aks-name>" \
  --resource-group "<aks-resource-group>" \
  --query nodeResourceGroup \
  -o tsv
```

Find the VMSS backing the new node pool:

```bash
NODE_RG=$(az aks show --name "<aks-name>" --resource-group "<aks-resource-group>" --query nodeResourceGroup -o tsv)

az vmss list \
  --resource-group "$NODE_RG" \
  --query "[?tags.\"aks-managed-poolName\"=='<nodepool-name>'].{name:name,id:id,identity:identity}" \
  -o json
```

The returned `identity.userAssignedIdentities` should include the `workload_identity_id` value configured in `terraform.tfvars`.

After the node pool is healthy, open the AutoMQ console and create an AutoMQ cluster.

## Defaults

- Autoscaling is enabled by default.
- The node pool uses the taint `dedicated=automq:NoSchedule`.
- Availability zones default to `["1", "2", "3"]`.
- If `orchestrator_version` is not set, the node pool Kubernetes version defaults to the existing AKS cluster version.
