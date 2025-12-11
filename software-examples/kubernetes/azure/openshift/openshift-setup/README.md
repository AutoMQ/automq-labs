# AutoMQ Enterprise on Azure OpenShift - Infrastructure Setup

This Terraform configuration prepares the Azure infrastructure for deploying AutoMQ Enterprise on Azure Red Hat OpenShift (ARO).

## Overview

This setup creates:
- **Virtual Network (VNet)**: Network infrastructure for OpenShift cluster
- **Subnets**: Master and Worker subnets for OpenShift control plane and worker nodes
- **Azure Blob Storage Account**: For AutoMQ S3 WAL and data storage
- **Storage Containers**: Separate containers for operations and data buckets
- **Managed Identity**: Service Principal for authentication to Azure Blob Storage

**Note**: OpenShift cluster creation is optional. You can either:
- **Option 1**: Let Terraform create the cluster (set `create_openshift_cluster = true` in `terraform.tfvars`)
- **Option 2**: Create the cluster manually through Azure Portal or Azure CLI (set `create_openshift_cluster = false`)

**Important**: The Terraform `azurerm_redhat_openshift_cluster` resource may not be available in all Azure provider versions. If you encounter errors, use Option 2 and create the cluster manually using the network outputs from Terraform.

## Prerequisites

1. **Azure Subscription**: With permissions to create resources
2. **Terraform**: Version >= 1.3.0
3. **Azure CLI**: For authentication (`az login`)
4. **Resource Provider**: Ensure `Microsoft.RedHatOpenShift` is registered:
   ```bash
   az provider register --namespace Microsoft.RedHatOpenShift
   ```

## Configuration

### 1. Create and Configure `terraform.tfvars`

**Important**: The `terraform.tfvars` file contains sensitive information and is excluded from git. 

First, copy the example file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then edit `terraform.tfvars` with your Azure details:

```hcl
location            = "eastus"
subscription_id     = "your-subscription-id"  # Replace with your Azure subscription ID
resource_group_name = "your-resource-group-name"
env_prefix          = "automq"
vnet_cidr           = "10.0.0.0/16"

# OpenShift Cluster Configuration
create_openshift_cluster = true
openshift_cluster_name   = "your-cluster-name"
master_vm_size          = "Standard_D8s_v3"
worker_vm_size          = "Standard_D4s_v3"
worker_node_count       = 3
```

**Network Configuration**:
- `vnet_cidr`: CIDR block for the Virtual Network (default: `10.0.0.0/16`)
  - Master subnet: `/27` (32 IPs) - minimum required by ARO
  - Worker subnet: `/24` (256 IPs) - for worker nodes

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review the Plan

```bash
terraform plan
```

### 4. Apply the Configuration

```bash
terraform apply
```

## Outputs

After applying, you'll get the following outputs:

**Network Outputs**:
- `vnet_id`: Virtual Network ID for OpenShift cluster
- `vnet_name`: Virtual Network name
- `master_subnet_id`: Master subnet ID for OpenShift control plane
- `worker_subnet_id`: Worker subnet ID for OpenShift worker nodes

**Storage Outputs**:
- `storage_account_name`: Name of the Azure Blob Storage account
- `storage_account_endpoint`: Primary blob endpoint (e.g., `https://saautomqxxxx.blob.core.windows.net`)
- `automq_data_bucket`: Container name for data storage
- `automq_ops_bucket`: Container name for operations storage

**Identity Outputs**:
- `workload_identity_client_id`: Client ID for Service Principal authentication
- `workload_identity_id`: Managed Identity Resource ID

## Next Steps

### 1. Create Azure Red Hat OpenShift Cluster

#### Option A: Create via Terraform (if supported)

If `create_openshift_cluster = true` in `terraform.tfvars`, Terraform will attempt to create the cluster. Configure the cluster settings:

```hcl
create_openshift_cluster = true
openshift_cluster_name   = "your-cluster-name"
master_vm_size          = "Standard_D8s_v5"
worker_vm_size          = "Standard_D4s_v5"
worker_node_count       = 3
```

**Note**: If Terraform reports that `azurerm_redhat_openshift_cluster` resource is not available, use Option B below.

#### Option B: Create via Azure CLI (Recommended)

Use the Terraform outputs to create the OpenShift cluster through Azure CLI:

```bash
# Get the network information from Terraform outputs
VNET_ID=$(terraform output -raw vnet_id)
MASTER_SUBNET_ID=$(terraform output -raw master_subnet_id)
WORKER_SUBNET_ID=$(terraform output -raw worker_subnet_id)
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
LOCATION=$(terraform output -raw location)

# Create ARO cluster
az aro create \
  --resource-group $RESOURCE_GROUP \
  --name <your-cluster-name> \
  --vnet $VNET_ID \
  --master-subnet $MASTER_SUBNET_ID \
  --worker-subnet $WORKER_SUBNET_ID \
  --location $LOCATION
```

After creation, get the cluster credentials:

```bash
az aro list-credentials \
  --resource-group $RESOURCE_GROUP \
  --name <your-cluster-name>
```

## Connect to the Cluster

### Option 1: Using the Automated Script (Recommended)

A convenient script is provided to connect to your cluster:

```bash
cd infra-setup/azure/openshift
./connect-cluster.sh
```

This script will:
- Automatically detect your cluster name and resource group from `terraform.tfvars`
- Retrieve the API server URL and credentials
- Log you in using `oc login` (if OpenShift CLI is installed)
- Provide instructions for using `kubectl` if `oc` is not available

You can also override the default values:

```bash
CLUSTER_NAME="your-cluster-name" RESOURCE_GROUP="your-resource-group" ./connect-cluster.sh
```

### Option 2: Using Azure CLI to Get Credentials

Get the kubeconfig automatically:

```bash
az aro get-credentials \
  --resource-group AutoMQ-lab-openshift \
  --name demobeihai
```

This will automatically configure `kubectl` to connect to your cluster.

### Option 3: Manual Connection Steps

1. **Get the API server URL:**

```bash
API_URL=$(az aro show \
  --resource-group AutoMQ-lab-openshift \
  --name demobeihai \
  --query "apiserverProfile.url" \
  --output tsv)
echo $API_URL
```

2. **Get kubeadmin credentials:**

```bash
az aro list-credentials \
  --resource-group AutoMQ-lab-openshift \
  --name demobeihai
```

3. **Login using OpenShift CLI (oc):**

```bash
oc login $API_URL \
  --username=kubeadmin \
  --password=<password-from-step-2> \
  --insecure-skip-tls-verify=true
```

4. **Or configure kubectl manually:**

```bash
kubectl config set-cluster demobeihai \
  --server=$API_URL \
  --insecure-skip-tls-verify=true

kubectl config set-credentials kubeadmin \
  --username=kubeadmin \
  --password=<password-from-step-2>

kubectl config set-context demobeihai \
  --cluster=demobeihai \
  --user=kubeadmin

kubectl config use-context demobeihai
```

5. **Verify connection:**

```bash
kubectl get nodes
oc get nodes  # if using OpenShift CLI
```

### Prerequisites

- **Azure CLI**: Must be installed and logged in (`az login`)
- **OpenShift CLI (oc)**: Recommended for OpenShift clusters. Download from [OpenShift CLI releases](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/)
- **kubectl**: Can be used as an alternative to `oc`

**Important**: Azure Red Hat OpenShift has specific network requirements:
- Subnets must be at least `/27` (32 IPs) for master nodes
- Subnets cannot have Network Security Groups (NSG) attached
- Subnets cannot have User Defined Routes (UDR)
- Service Endpoints are enabled for `Microsoft.Storage` and `Microsoft.ContainerRegistry`

### 2. Configure AutoMQ Enterprise Helm Values

Use the Terraform outputs to configure your Helm values file:

```yaml
global:
  cloudProvider:
    name: azure
    credentials: static://?accessKey=<storage-account-key>&secretKey=<storage-account-key>
  config: |
    s3.ops.buckets=1@s3://<automq-ops-bucket>?region=<region>&endpoint=<storage-account-endpoint>&pathStyle=true
    s3.data.buckets=0@s3://<automq-data-bucket>?region=<region>&endpoint=<storage-account-endpoint>&pathStyle=true
    s3.wal.path=0@s3://<automq-data-bucket>?region=<region>&endpoint=<storage-account-endpoint>&pathStyle=true
```

**Note**: For Service Principal authentication, you'll need to configure the credentials differently. See the AutoMQ Enterprise documentation for details.

### 3. Deploy AutoMQ Enterprise

```bash
helm install automq-release oci://automq.azurecr.io/helm/automq-enterprise-chart \
  -f values.yaml \
  --namespace automq \
  --create-namespace
```

## Service Principal Authentication

The Managed Identity created by this Terraform configuration can be used for Service Principal authentication. You'll need:

- **Client ID**: From `workload_identity_client_id` output
- **Client Secret**: Create a secret for the Service Principal
- **Tenant ID**: Your Azure AD tenant ID

## Network Requirements

### Azure OpenShift (ARO) Network Constraints

The network infrastructure created by this Terraform configuration follows ARO requirements:

1. **Subnet Requirements**:
   - Master subnet: Minimum `/27` (32 IPs) - configured as `/27`
   - Worker subnet: Recommended `/24` (256 IPs) - configured as `/24`
   - Subnets must be dedicated (no other resources)

2. **Subnet Restrictions**:
   - ❌ No Network Security Groups (NSG) allowed
   - ❌ No User Defined Routes (UDR) allowed
   - ✅ Service Endpoints enabled for Azure services

3. **Service Endpoints**:
   - `Microsoft.Storage` - for Azure Blob Storage access
   - `Microsoft.ContainerRegistry` - for container registry access

### AutoMQ Deployment Network Configuration

For AutoMQ Enterprise deployment on OpenShift:
- **Controller Service**: Use ClusterIP or NodePort (not LoadBalancer)
- **Broker Service**: Use Pod IP addresses for direct access
- **Kafka ACL**: Can use Plaintext authentication

## Cleanup

To remove all resources:

```bash
terraform destroy
```

## Troubleshooting

### Storage Account Access

If you need to access the storage account keys:

```bash
az storage account keys list \
  --resource-group <resource-group-name> \
  --account-name <storage-account-name>
```

### Verify Containers

```bash
az storage container list \
  --account-name <storage-account-name> \
  --account-key <storage-key>
```

## Adding Node Groups

To add additional worker node groups (e.g., for AutoMQ dedicated nodes), see [NODE_GROUPS.md](./NODE_GROUPS.md) for detailed instructions.

**Quick Summary**:
- Terraform only supports **one worker_profile** during cluster creation
- Additional node groups must be added **after** cluster creation using:
  - Azure CLI: `az aro node-pool add`
  - OpenShift Machine Sets (native OpenShift API)

## Related Documentation

- [AutoMQ Enterprise Helm Chart](https://www.automq.com/docs/automq-cloud/appendix/deploy-automq-enterprise-via-helm-chart)
- [Azure Red Hat OpenShift Documentation](https://learn.microsoft.com/azure/openshift/)
- [Azure Blob Storage Documentation](https://learn.microsoft.com/azure/storage/blobs/)
- [Adding Node Groups Guide](./NODE_GROUPS.md)

