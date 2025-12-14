# Deploy AutoMQ Enterprise on Azure Red Hat OpenShift

This guide provides instructions for deploying the enterprise version of [AutoMQ](https://www.automq.com/) on Azure Red Hat OpenShift (ARO) using the managed Helm chart. This example demonstrates deploying AutoMQ in **S3 WAL mode** using Azure Blob Storage as the backend storage.

AutoMQ is a  diskless Kafka® on S3 that is fully compatible with the Kafka protocol. This deployment leverages Azure Blob Storage for Write-Ahead Log (WAL) storage, providing scalable and cost-effective storage for your streaming workloads.

## Prerequisites

Before you begin, ensure you have the following:

1. **Azure Red Hat OpenShift Cluster**: If you don't have one, you can provision a cluster using the Terraform configuration provided in the [`openshift-setup`](./openshift-setup/) directory. See the [OpenShift Setup Guide](./openshift-setup/README.md) for detailed instructions.

2. **Azure Blob Storage Containers**: You need Azure Blob Storage containers for AutoMQ operations and data storage. The Terraform setup in `openshift-setup` can automatically create these resources, or you can create them manually:
   - Operations bucket (for AutoMQ operations data)
   - Data bucket (for AutoMQ data and WAL)

3. **StorageClass**: AutoMQ Controller requires a PersistentVolumeClaim (PVC) to store metadata. Create the StorageClass using the provided configuration:
   ```bash
   kubectl apply -f storage/storageclass-premium-ssd.yaml
   ```

4. **Helm (v3.6.0+)**: The package manager for Kubernetes. Verify your installation:
   ```bash
   helm version
   ```
   If needed, follow the official [Helm installation guide](https://helm.sh/docs/intro/install/).

5. **OpenShift CLI (oc) or kubectl**: Configured to access your OpenShift cluster.

## Resource Requirements

### Node Specifications

Based on AutoMQ's recommended resource requirements, ensure your OpenShift worker nodes meet the following specifications:

- **Recommended VM Size**: `Standard_D4s_v3` (4 vCPUs, 16 GiB memory)
- **Minimum Resources per Pod**:
  - CPU: 2000m (request) / 4000m (limit)
  - Memory: 12Gi (request) / 16Gi (limit)

Ensure your cluster has sufficient resources to accommodate the AutoMQ deployment. The default configuration deploys at least 3 Controller replicas, each requiring the resources specified above.

## Installation Steps

### 1. Prepare Infrastructure Resources

#### Option A: Using Terraform (Recommended)

Navigate to the `openshift-setup` directory and create a custom `terraform.tfvars` file based on the provided template:

```bash
cd openshift-setup
# Copy the example template and customize it with your Azure credentials
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values
```

Edit `terraform.tfvars` and replace the placeholder values with your Azure configuration:
- `location`: Your Azure region (e.g., `eastus`)
- `subscription_id`: Your Azure subscription ID
- `resource_group_name`: Desired resource group name
- `env_prefix`: Short prefix for resource naming
- `openshift_cluster_name`: Your desired OpenShift cluster name
- `worker_vm_size`: VM size for worker nodes (recommended: `Standard_D4s_v3`)
- `worker_node_count`: Number of worker nodes

Then initialize and apply the Terraform configuration:

```bash
terraform init
terraform apply
```

This will create:
- Azure Red Hat OpenShift cluster
- Azure Blob Storage account and containers
- Required networking resources

#### Option B: Manual Setup

If you prefer to set up resources manually:

1. **Create OpenShift Cluster**: Use Azure Portal or Azure CLI to create an ARO cluster
2. **Create Storage Account and Containers**: Create an Azure Storage Account and two Blob containers (one for operations, one for data)

### 2. Create StorageClass

AutoMQ Controller requires persistent storage for metadata. Apply the provided StorageClass:

```bash
kubectl apply -f storage/storageclass-premium-ssd.yaml
```

### 3. Create Service Principal for Azure Blob Storage Access

AutoMQ requires a Service Principal to access Azure Blob Storage. Follow these steps to create and configure it:

#### Step 1: Create App Registration in Entra ID (Azure AD)

1. Navigate to **Azure Portal** → **Microsoft Entra ID** → **App registrations**
2. Click **New registration**
3. Enter a name for your application (e.g., `automq-storage-access`)
4. Select **Accounts in this organizational directory only**
5. Click **Register**
6. After creation, note down the following values from the **Overview** page:
   - **Application (client) ID**: This will be your `<client-id>`
   - **Directory (tenant) ID**: This will be your `<tenant-id>`
   - **Secret Balue**: This will be your `<secret-value>`

#### Step 2: Grant Storage Account Permissions

1. Navigate to your **Storage Account** in Azure Portal
2. Go to **Access control (IAM)**
3. Click **Add** → **Add role assignment**
4. Select the role **Storage Blob Data Contributor** (or **Storage Blob Data Owner** for full access)
5. In the **Assign access to** dropdown, select **User, group, or service principal**
6. Click **Select members** and search for your App Registration name


### 4. Configure Helm Values

Edit the `automq-values.yaml` file and customize it for your environment. You need to replace the placeholder values:

**Key Configuration Areas:**

1. **Azure Blob Storage Configuration**:
   ```yaml
   global:
     config: |
       s3.ops.buckets=1@azblob://<your-ops-bucket>?region=<az-region>&endpoint=<endpoint-url>&authType=static
       s3.data.buckets=0@azblob://<your-data-bucket>?region=<az-region>&endpoint=<endpoint-url>&authType=static
       s3.wal.path=0@azblob://<your-data-bucket>?region=<az-region>&endpoint=<endpoint-url>&authType=static
   ```

2. **Service Principal Credentials** (Static Authentication):
   ```yaml
   global:
     credentials: "static://?accessKey=<client-id>&secretKey=<secret-value>&tenant=<tenant-id>"
   ```

3. **Resource Limits**: Adjust based on your node capacity (default uses Standard_D4s_v3 recommendations)

4. **StorageClass**: Ensure it matches the StorageClass you created:
   ```yaml
   controller:
     persistence:
       metadata:
         storageClass: "automq-disk-azure-premium-ssd"
   ```

**Important**: Replace all placeholder values marked with `<...>`:
- `<your-ops-bucket>`: Your Azure Blob Storage operations container name
- `<your-data-bucket>`: Your Azure Blob Storage data container name
- `<az-region>`: Your Azure region (e.g., `eastus`)
- `<endpoint-url>`: Your storage account blob endpoint (e.g., `https://<storage-account>.blob.core.windows.net`)
- `<client-id>`: Service Principal Client ID (Application ID from App Registration)
- `<secret-value>`: Service Principal Client Secret (from the client secret you created)
- `<tenant-id>`: Azure Tenant ID (Directory ID from App Registration)

For more details on available parameters, refer to:
- [AutoMQ Enterprise Helm Chart Values](https://www.automq.com/docs/automq-cloud/appendix/helm-chart-values-readme)
- [AutoMQ Enterprise Installation Guide](https://www.automq.com/docs/automq-cloud/appendix/deploy-automq-enterprise-via-helm-chart#install-automq)
- [AutoMQ Performance Tuning Guide](https://www.automq.com/docs/automq/deployment/performance-tuning-for-broker)

### 5. Install AutoMQ Enterprise

Once your `automq-values.yaml` file is configured, deploy AutoMQ using Helm. Replace `<namespace>` with your desired namespace name:

```bash
helm install <release-name> oci://automq.azurecr.io/helm/automq-enterprise-chart \
  -f automq-values.yaml \
  --version 5.3.2 \
  --namespace <namespace> \
  --create-namespace
```

#### 5.1. Configure Security Context Constraints (SCC)

OpenShift introduces an additional security layer called **Security Context Constraints (SCC)** that restricts pod permissions beyond standard Kubernetes. SCC acts as an intermediate authorization layer that controls what security contexts pods can use, including user IDs, capabilities, and volume types.


AutoMQ pods may require specific security contexts (such as running as a specific user ID or mounting certain volume types) that are restricted by OpenShift's default SCC policies. Without proper SCC permissions, AutoMQ pods may fail to start or encounter permission errors.


1. First, identify the ServiceAccount used by AutoMQ pods. Wait for the pods to be created, then run:

```bash
oc get pod <pod-name> -n <namespace> -o jsonpath='{.spec.serviceAccountName}'
```

Replace `<pod-name>` with the actual name of an AutoMQ pod (e.g., `automq-controller-0`) and `<namespace>` with your namespace.

2. Grant the `anyuid` SCC to the ServiceAccount. This allows pods to run as any user ID, which is often required for applications that need specific user permissions:

```bash
oc adm policy add-scc-to-user anyuid -z <serviceAccountName> -n <namespace>
```

Replace `<serviceAccountName>` with the ServiceAccount name obtained from step 1 (typically `automq-enterprise-controller` or similar), and `<namespace>` with your namespace.

### 6. Verify Deployment

Check the deployment status (replace `<namespace>` with your namespace):

```bash
# Check pods
kubectl get pods -n <namespace>

# Check services
kubectl get svc -n <namespace>

# Check PVCs
kubectl get pvc -n <namespace>
```

Wait for all Controller pods to be in `Running` state before proceeding.

### 7. Access and Verify AutoMQ

Once the deployment is complete, you can access AutoMQ using the Kubernetes service DNS name. The service follows the pattern `[service-name].[namespace]`.

#### Get Service Information

```bash
# List all services in your namespace
kubectl get svc -n <namespace>

# Get detailed information about the AutoMQ service
kubectl get svc <service-name> -n <namespace> -o yaml
```

#### Connect to AutoMQ

AutoMQ services are accessible within the cluster using the following DNS pattern:

```
<service-name>.<namespace>.svc.cluster.local
```

Or simply:

```
<service-name>.<namespace>
```

**Example**: If your service is named `automq` in namespace `automq-software`, you can connect using:

```
automq-automq-enterprise-controller-headless.automq-software.svc.cluster.local:9092
```



## Configuration Details

### S3 WAL Mode

This deployment uses **S3 WAL mode**, where:
- Write-Ahead Logs (WAL) are stored in Azure Blob Storage
- Metadata is stored on persistent volumes (PVCs)
- Data is streamed directly to/from Azure Blob Storage

This architecture provides:
- **Scalability**: Unlimited storage capacity via Azure Blob Storage
- **Cost Efficiency**: Pay only for storage used
- **Durability**: Azure Blob Storage provides high durability guarantees

### Authentication

This example uses **static authentication** with Service Principal credentials:
- Service Principal Client ID (or Storage Account name) as access key
- Service Principal Client Secret (or Storage Account key) as secret key
- Azure Tenant ID

For production environments, consider using Managed Identity (Workload Identity) for enhanced security.

## Managing the Deployment

### Upgrading

To apply changes after updating `automq-values.yaml` (replace `<release-name>` and `<namespace>` with your values):

```bash
helm upgrade <release-name> oci://automq.azurecr.io/helm/automq-enterprise-chart \
  -f automq-values.yaml \
  --version 5.3.2 \
  --namespace <namespace>
```

### Uninstalling

To remove the deployment (replace `<release-name>` and `<namespace>` with your values):

```bash
helm uninstall <release-name> --namespace <namespace>
```

**Note**: This will delete all AutoMQ data. Ensure you have backups if needed.

## Troubleshooting

### Pod Startup Issues

If pods fail to start, check:

1. **Resource Availability**: Ensure nodes have sufficient CPU and memory
2. **StorageClass**: Verify the StorageClass exists and is accessible
3. **Azure Credentials**: Verify Service Principal credentials are correct
4. **Network Connectivity**: Ensure pods can reach Azure Blob Storage endpoints


## Additional Resources

- [AutoMQ Enterprise](https://www.automq.com/docs/automq-cloud/appendix/deploy-automq-enterprise-via-helm-chart)
- [Azure Red Hat OpenShift Documentation](https://learn.microsoft.com/azure/openshift/)


## Future Enhancements

We are continuously improving this example and plan to provide additional configurations for:

- **Observability**: Prometheus, Grafana, and OpenTelemetry integration examples for monitoring AutoMQ on OpenShift
- **Performance Testing**: Load testing and benchmarking configurations
- **More Examples**: Additional deployment patterns and use cases

We welcome your feedback and contributions. If you encounter any issues or have suggestions for improvements, please reach out to the AutoMQ team.

