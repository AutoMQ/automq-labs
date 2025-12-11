# AutoMQ Node Pool Module for Azure Red Hat OpenShift

This module creates dedicated worker nodes for AutoMQ workloads on Azure Red Hat OpenShift (ARO) clusters.

## Overview

Since Azure Red Hat OpenShift doesn't support multiple `worker_profile` blocks in Terraform, this module uses OpenShift Machine Sets to add dedicated AutoMQ nodes after cluster creation.

**Network Architecture**: This module uses a dedicated subnet (`10.0.2.0/24`) for AutoMQ nodes, separate from the default worker subnet (`10.0.1.0/24`). This provides:
- **Network isolation**: Better organization and management of IP addresses
- **Future flexibility**: Can apply different network policies or NSG rules if needed
- **Best practices**: Follows production-ready network design patterns
- **Note**: Nodes in different subnets within the same VNet can still communicate with each other by default

## Features

Based on the `nodepool-automq` module reference, this implementation provides:

- **Dedicated nodes**: Isolated nodes specifically for AutoMQ workloads
- **Node taints**: `dedicated=automq:NoSchedule` to prevent other workloads from scheduling
- **Node labels**: `node-role.kubernetes.io/automq` for easy node selection
- **Multi-zone support**: Nodes distributed across 3 availability zones
- **Configurable VM size**: Default `Standard_D4s_v3` (matching nodepool-automq)
- **Configurable node count**: Default 3 nodes (1 per zone)

## Usage

### 1. Enable in terraform.tfvars

```hcl
create_automq_node_pool = true
automq_node_pool_vm_size = "Standard_D4s_v3"  # Same as nodepool-automq default
automq_node_pool_count   = 3
```

### 2. Apply Terraform

```bash
terraform apply
```

**Important**: Before applying, make sure you're logged into the OpenShift cluster:

```bash
# Login to the cluster first
./connect-cluster.sh
# Or manually:
oc login <api-url> -u kubeadmin -p <password> --insecure-skip-tls-verify=true
```

The module will automatically create Machine Sets for AutoMQ nodes.

### 3. Verify Nodes

After a few minutes, check that nodes are created:

```bash
# Check Machine Sets
oc get machinesets -n openshift-machine-api | grep automq

# Check nodes
oc get nodes -l node-role.kubernetes.io/automq

# Check node labels and taints
oc get nodes -l node-role.kubernetes.io/automq -o yaml | grep -A 5 "labels:"
```

## Configuration

### Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `cluster_name` | ARO cluster name | Required | `demobeihai` |
| `resource_group_name` | Azure resource group | Required | `AutoMQ-lab-openshift` |
| `subnet_id` | Subnet ID for AutoMQ nodes | Required | From `module.network.automq_subnet_id` |
| `vm_size` | VM size for nodes | `Standard_D4s_v3` | `Standard_D4s_v3`, `Standard_D8s_v3` |
| `node_count` | Total number of nodes | `3` | `3`, `6`, `9` |
| `disk_size_gb` | Disk size per node | `128` | `128`, `256` |
| `location` | Azure region | Required | `eastus` |

### Node Configuration

The nodes are configured with:

- **Taints**: `dedicated=automq:NoSchedule` - Prevents other pods from scheduling
- **Labels**: 
  - `node-role.kubernetes.io/worker: ""`
  - `node-role.kubernetes.io/automq: ""`
  - `dedicated: "automq"`

### Using AutoMQ Nodes in Deployments

To schedule AutoMQ pods on these nodes, add tolerations and node selectors:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: automq-broker
spec:
  template:
    spec:
      tolerations:
        - key: dedicated
          operator: Equal
          value: automq
          effect: NoSchedule
      nodeSelector:
        node-role.kubernetes.io/automq: ""
      containers:
        - name: automq
          # ...
```

Or in Helm values:

```yaml
nodeSelector:
  node-role.kubernetes.io/automq: ""
tolerations:
  - key: dedicated
    operator: Equal
    value: automq
    effect: NoSchedule
```

## Comparison with nodepool-automq (AKS)

| Feature | AKS (nodepool-automq) | ARO (this module) |
|---------|----------------------|------------------|
| Resource Type | `azurerm_kubernetes_cluster_node_pool` | OpenShift Machine Sets |
| Auto Scaling | Supported | Manual (via Machine Set replicas) |
| Spot Instances | Supported | Not implemented |
| Node Taints | `dedicated=automq:NoSchedule` | `dedicated=automq:NoSchedule` |
| Default VM Size | `Standard_D4s_v3` | `Standard_D4s_v3` |
| Zones | `[1, 2, 3]` | Distributed across 3 zones |

## Manual Creation (Alternative)

If you prefer to create Machine Sets manually, you can use the script directly:

```bash
./modules/automq-nodepool/create-machineset.sh \
  demobeihai \
  AutoMQ-lab-openshift \
  <subnet-id> \
  Standard_D4s_v3 \
  3 \
  128 \
  eastus
```

## Cleanup

To remove AutoMQ nodes:

```bash
# Delete Machine Sets
oc delete machineset -n openshift-machine-api -l machine.openshift.io/cluster-api-machineset | grep automq

# Or delete specific Machine Sets
oc delete machineset <cluster-id>-automq-<zone> -n openshift-machine-api
```

## Troubleshooting

### Nodes not appearing

1. Check Machine Sets are created:
   ```bash
   oc get machinesets -n openshift-machine-api
   ```

2. Check Machine Set status:
   ```bash
   oc describe machineset <machineset-name> -n openshift-machine-api
   ```

3. Check Machines:
   ```bash
   oc get machines -n openshift-machine-api
   ```

4. Check for errors in Machine Set events:
   ```bash
   oc get events -n openshift-machine-api --sort-by='.lastTimestamp' | grep automq
   ```

### Script fails with "Could not get cluster ID"

Make sure you're logged into the OpenShift cluster:

```bash
oc login <api-url> -u kubeadmin -p <password> --insecure-skip-tls-verify=true
```

### Subnet issues

Ensure the AutoMQ subnet:
- Has at least `/27` (32 IPs)
- Has no Network Security Groups attached
- Has no User Defined Routes
- Has Service Endpoints enabled for `Microsoft.Storage` and `Microsoft.ContainerRegistry`

## References

- [OpenShift Machine Sets Documentation](https://docs.openshift.com/container-platform/latest/machine_management/creating_machinesets/creating-machineset-azure.html)
- [Azure Red Hat OpenShift Documentation](https://learn.microsoft.com/azure/openshift/)
- [nodepool-automq module](../byoc-examples/setup/azure/azure-automq-env/modules/nodepool-automq/) - Reference implementation for AKS

