# AutoMQ-ready GKE cluster

This Terraform example provisions a regional GKE Standard cluster and the network resources required to run AutoMQ.

## Architecture

The example creates:

- A dedicated VPC.
- A management subnet for a future AutoMQ Console or bastion.
- A workload subnet with secondary ranges for GKE Pods and Services.
- A Cloud Router and Cloud NAT covering both subnets.
- A regional GKE Standard cluster with private nodes and a public control-plane endpoint.
- The GKE default node pool for system workloads.
- One dedicated AutoMQ node pool spanning three zones.
- A firewall rule allowing the management subnet to reach AutoMQ workload nodes.

The cluster uses the GKE Stable release channel, Dataplane V2, Workload Identity, GKE Metadata Server, NodeLocal DNSCache, and the GCE Persistent Disk CSI driver.

This example does not create an AutoMQ Console, buckets, Cloud DNS zones, Data Plane identities, Kubernetes Service Accounts, or an AutoMQ Instance.

## Prerequisites

- Terraform 1.3 or later.
- `gcloud` and `kubectl`.
- A GCP project with billing enabled.
- Application Default Credentials:

  ```bash
  gcloud auth application-default login
  ```

- `serviceusage.googleapis.com` enabled before running Terraform. Terraform enables `compute.googleapis.com` and `container.googleapis.com` and leaves them enabled during destroy.
- Permissions to enable project services and create VPC, firewall, Cloud NAT, and GKE resources.
- A usable default Compute Engine Service Account for GKE nodes.

## Deploy

1. Create a local variables file:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Set `project_id`, `region`, and exactly three zones in `terraform.tfvars`. The zones must belong to the selected region.

3. Initialize and review the deployment:

   ```bash
   terraform init
   terraform plan
   ```

4. Apply the configuration:

   ```bash
   terraform apply
   ```

5. Print and run the generated credentials command:

   ```bash
   terraform output -raw get_credentials_command
   ```

## Verify

Verify the regional node placement and the dedicated AutoMQ taint:

```bash
kubectl get nodes -L topology.kubernetes.io/zone,node_type
kubectl describe nodes | grep -A3 Taints
```

The cluster has one default node pool and one AutoMQ node pool. Each pool spans the same three zones; Terraform does not create one node pool per zone.

## Configuration

| Input | Description | Default |
| --- | --- | --- |
| `project_id` | GCP project for all resources | Required |
| `region` | Region for the regional GKE cluster | Required |
| `zones` | Exactly three distinct zones used by both node pools | Required |
| `name_prefix` | Prefix for generated resource names | `automq` |
| `network_cidrs` | Management, workload, Pod, and Service CIDRs | See `terraform.tfvars.example` |
| `automq_node_pool.machine_type` | AutoMQ node machine type | `n2d-standard-4` |
| `automq_node_pool.min_size` | Minimum total nodes across the three zones | `3` |
| `automq_node_pool.max_size` | Maximum total nodes across the three zones | `10` |

To use an Arm-based Tau T2A machine, set `automq_node_pool.machine_type` to a suitable `t2a-standard-*` type and choose three zones where that type is available. Workloads scheduled to that pool must provide Arm64-compatible images.

When overriding `network_cidrs`, use non-overlapping IPv4 ranges that do not conflict with connected VPC, VPN, or on-premises networks.

## Outputs

The root module outputs the canonical GKE, VPC, and subnet resource IDs, the AutoMQ node pool name, the Workload Identity pool, and a `gcloud` credentials command. It does not output access tokens, kubeconfig contents, the cluster CA, or the default Compute Engine Service Account.

## Network access

GKE nodes use private IP addresses and reach external services through Cloud NAT. The GKE control-plane endpoint remains public and uses GKE authentication and authorization; Master Authorized Networks is not enabled in this example.

The root firewall rule allows the management subnet to reach AutoMQ workload nodes on the ports used by the AutoMQ deployment. Add separate, narrowly scoped rules for Kafka clients or other external subnets.

## Cleanup

Delete any AutoMQ resources using the cluster before destroying the infrastructure:

```bash
terraform destroy
```

`deletion_protection` is disabled so the example can be destroyed through Terraform.
