# Terraform for AutoMQ on GKE

This Terraform example provisions a GKE Standard cluster and the network
resources needed to run AutoMQ.

## Resources

- A dedicated VPC.
- A management subnet that can host the AutoMQ BYOC Console or other management
  clients.
- A workload subnet with secondary ranges for GKE Pods and Services.
- A Cloud Router and Cloud NAT for private GKE node egress.
- A regional GKE Standard cluster with private nodes and a public control-plane
  endpoint.
- The GKE default node pool for system workloads.
- One dedicated AutoMQ node pool spanning three zones.
- A firewall rule allowing the management subnet to reach the required AutoMQ
  workload ports.

The cluster uses the GKE Stable release channel, Dataplane V2, Workload
Identity, GKE Metadata Server, NodeLocal DNSCache, and the GCE Persistent Disk
CSI driver.

This example does not deploy the AutoMQ BYOC Console. Use the
[GCP Console example](../../../gcp/terraform/) after the network and cluster
are ready.

## Prerequisites

- Terraform 1.3 or later.
- `gcloud` and `kubectl`.
- A GCP project with billing enabled.
- Application Default Credentials:

  ```bash
  gcloud auth application-default login
  ```

- `serviceusage.googleapis.com` enabled before running Terraform. Terraform
  enables the Compute Engine and GKE APIs and leaves them enabled during
  destroy.
- Permissions to enable project services and create VPC and GKE resources.
- A usable default Compute Engine service account for GKE nodes.

## Deploy

1. Create a local variables file:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Set `project_id`, `region`, and exactly three zones.

3. Initialize, review, and apply:

   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. Configure `kubectl`:

   ```bash
   terraform output -raw get_credentials_command
   ```

   Run the command printed by Terraform.

## Verify

Verify regional node placement and the dedicated AutoMQ taint:

```bash
kubectl get nodes -L topology.kubernetes.io/zone,node_type
kubectl describe nodes | grep -A3 Taints
```

The cluster has one default node pool and one AutoMQ node pool. Each pool spans
the same three zones; Terraform does not create one node pool per zone.

## Console Handoff

The GCP Console example needs the network outputs from this setup:

```bash
terraform output -raw vpc_id
terraform output -raw management_subnet_id
```

Use them as `network_id` and `management_subnet_id` in
`byoc-examples/setup/gcp/terraform/terraform.tfvars`.

## Configuration

| Input | Description | Default |
| --- | --- | --- |
| `project_id` | GCP project for all resources | Required |
| `region` | Region for the GKE cluster | Required |
| `zones` | Exactly three distinct zones used by both node pools | Required |
| `name_prefix` | Prefix for generated resource names | `automq` |
| `network_cidrs` | Management, workload, Pod, and Service CIDRs | See `terraform.tfvars.example` |
| `automq_node_pool.machine_type` | AutoMQ node machine type | `n4d-standard-2` |
| `automq_node_pool.min_size` | Minimum total nodes across the three zones | `3` |
| `automq_node_pool.max_size` | Maximum total nodes across the three zones | `10` |

Supported AutoMQ node machine types are `n4d-standard-2`, `n4d-highmem-2`,
`n4a-highmem-1`, `n4a-standard-2`, and `n4d-standard-4`. Confirm that the
selected type is available in all three zones. The AutoMQ node pool uses
`hyperdisk-balanced` boot disks, as required by these N4 machine families.

When overriding `network_cidrs`, use non-overlapping IPv4 ranges that do not
conflict with connected VPC, VPN, or on-premises networks.

## Security Notes

GKE nodes use private IP addresses and reach external services through Cloud
NAT. The GKE control-plane endpoint remains public and uses GKE authentication
and authorization; Master Authorized Networks is not enabled in this example.

The management subnet can reach AutoMQ workload nodes only on the required
ports. Add separate, narrowly scoped rules for Kafka clients in other subnets.

## Cleanup

Delete workloads using the cluster before destroying it:

```bash
terraform destroy
```
