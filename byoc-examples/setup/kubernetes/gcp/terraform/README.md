# AutoMQ BYOC environment on GCP

This Terraform example provisions a complete AutoMQ BYOC environment on GCP: a dedicated VPC, a regional GKE Standard cluster, and an AutoMQ Console VM.

## Architecture

The example creates:

- A dedicated VPC.
- A management subnet for the AutoMQ Console.
- A workload subnet with secondary ranges for GKE Pods and Services.
- A Cloud Router and Cloud NAT covering both subnets.
- A regional GKE Standard cluster with private nodes and a public control-plane endpoint.
- The GKE default node pool for system workloads.
- One dedicated AutoMQ node pool spanning three zones.
- An AutoMQ Console VM with a static public endpoint and persistent data disk.
- A Console service account and its GCP control-plane permissions.
- Firewall rules for Console access and Console-to-AutoMQ traffic.

The cluster uses the GKE Stable release channel, Dataplane V2, Workload Identity, GKE Metadata Server, NodeLocal DNSCache, and the GCE Persistent Disk CSI driver.

This example does not create an AutoMQ Instance. After the environment is ready, use the Console or the `automq/automq` Terraform provider with the output endpoint and access keys. The Console creates the environment's Ops Bucket during bootstrap and each Instance's Data Bucket and DNS Zone when the Instance is created.

## Prerequisites

- Terraform 1.3 or later.
- `gcloud` and `kubectl`.
- A GCP project with billing enabled.
- A GCP BYOC installation configuration from AutoMQ containing the base64 `CONFIG` value and Console image.
- Application Default Credentials:

  ```bash
  gcloud auth application-default login
  ```

- `serviceusage.googleapis.com` enabled before running Terraform. Terraform enables the remaining Compute, GKE, DNS, IAM, Storage, and Resource Manager APIs and leaves them enabled during destroy.
- Permissions to enable project services and create VPC, GKE, Compute Engine, IAM, Cloud DNS, and GCS resources.
- A usable default Compute Engine service account for GKE nodes.

## Deploy

1. Create a local variables file:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Set `project_id`, `region`, exactly three zones, `automq_config`, and `automq_console_image` in `terraform.tfvars`.

3. If the Console image is private, also set all fields in `automq_console_registry`.

4. Initialize, review, and apply:

   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

5. Open the Console:

   ```bash
   terraform output -raw console_endpoint
   terraform output -raw console_initial_password
   ```

   The initial username is `admin`.

6. Configure `kubectl`:

   ```bash
   terraform output -raw get_credentials_command
   ```

## Verify

Verify the Console endpoint:

```bash
curl -I "$(terraform output -raw console_endpoint)"
```

Verify regional node placement and the dedicated AutoMQ taint:

```bash
kubectl get nodes -L topology.kubernetes.io/zone,node_type
kubectl describe nodes | grep -A3 Taints
```

The cluster has one default node pool and one AutoMQ node pool. Each pool spans the same three zones; Terraform does not create one node pool per zone.

## AutoMQ provider

The Console module generates an initial access key pair for automation. Read the values without placing them in a committed `tfvars` file:

```bash
terraform output -raw console_endpoint
terraform output -raw console_initial_access_key
terraform output -raw console_initial_secret_key
terraform output -raw automq_environment_id
```

Use these values with provider `automq/automq` to create an `automq_kafka_instance`. The GKE cluster ID and workload subnet ID are available as `gke_cluster_id` and `workload_subnet_id`.

## Configuration

| Input | Description | Default |
| --- | --- | --- |
| `project_id` | GCP project for all resources | Required |
| `region` | Region for the environment | Required |
| `zones` | Exactly three distinct zones used by both node pools | Required |
| `name_prefix` | Prefix for generated resource names | `automq` |
| `automq_config` | Base64 `CONFIG` value containing the BYOC environment settings | Required |
| `automq_console_image` | GCP Console container image from AutoMQ | Required |
| `automq_home_endpoint` | AutoMQ Cloud endpoint | `https://console.automq.cloud` |
| `automq_console_registry` | Optional private registry credentials | Empty |
| `console_machine_type` | Console VM machine type | `e2-standard-2` |
| `console_ingress_source_ranges` | CIDRs allowed to access Console port 8080 | `0.0.0.0/0` |
| `network_cidrs` | Management, workload, Pod, and Service CIDRs | See `terraform.tfvars.example` |
| `automq_node_pool.machine_type` | AutoMQ node machine type | `n2d-standard-4` |
| `automq_node_pool.min_size` | Minimum total nodes across the three zones | `3` |
| `automq_node_pool.max_size` | Maximum total nodes across the three zones | `10` |

To use an Arm-based Tau T2A machine, set `automq_node_pool.machine_type` to a suitable `t2a-standard-*` type and choose three zones where that type is available. Workloads scheduled to that pool must provide Arm64-compatible images.

When overriding `network_cidrs`, use non-overlapping IPv4 ranges that do not conflict with connected VPC, VPN, or on-premises networks.

## Security notes

GKE nodes use private IP addresses and reach external services through Cloud NAT. The GKE control-plane endpoint remains public and uses GKE authentication and authorization; Master Authorized Networks is not enabled in this example.

The Console endpoint is public so the example is easy to access. Restrict `console_ingress_source_ranges` to trusted public CIDRs. The management subnet can reach AutoMQ workload nodes only on the required ports; add separate, narrowly scoped rules for Kafka clients.

The Console service account uses broad control-plane permissions so it can manage GKE, IAM, DNS, and instance resources. The bootstrap client secret, registry password, and generated Console credentials are stored in Terraform state and GCE instance metadata. Protect the state and use a hardened secret-delivery and IAM design for production.

## Cleanup

Delete AutoMQ Instances using the cluster before destroying the environment:

```bash
terraform destroy
```

The Console-created Ops Bucket is outside Terraform state; delete it separately after the environment is no longer used.
