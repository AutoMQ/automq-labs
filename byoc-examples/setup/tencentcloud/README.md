# AutoMQ on Tencent Cloud

This directory contains Terraform configurations for deploying AutoMQ on Tencent Cloud.

## Subdirectories

### [`automq-deploy-env/`](./automq-deploy-env/)

The main Terraform configuration for deploying a complete AutoMQ environment into an existing VPC. It provisions:

- A TKE (Tencent Kubernetes Engine) managed cluster in VPC-CNI mode.
- A system node pool (Spot) for cluster components.
- An AutoMQ workload node pool with dedicated taint (`dedicated=automq:NoSchedule`), supporting Spot, on-demand, and monthly subscription (prepaid) billing modes.
- COS buckets for ops and data storage, with bucket policy for cross-account access.
- CAM role and policy for node pool access to COS.
- A Private DNS zone for the AutoMQ console.
- (Optional) An AutoMQ console CVM instance with EIP, CBS data disk, SSH key pair, dedicated security group, and CAM role.

## Prerequisites

- Terraform >= 1.3
- Tencent Cloud account with appropriate permissions
- Tencent Cloud credentials configured (e.g., `TENCENTCLOUD_SECRET_ID` and `TENCENTCLOUD_SECRET_KEY` environment variables)
- An existing VPC with subnets across one or more availability zones

## Quick Start

1. Copy the example variables file and fill in your values:

```bash
cd automq-deploy-env
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` according to the comments in the file. See [`terraform.tfvars.example`](./automq-deploy-env/terraform.tfvars.example) for a full reference of all available parameters.

2. Deploy:

```bash
terraform init
terraform plan
terraform apply
```

3. Get the kubeconfig:

```bash
# Intranet endpoint (always available)
terraform output -raw kube_config_intranet > ~/.kube/automq-tke-config

# Internet endpoint (only when enable_cluster_internet = true)
# terraform output -raw kube_config > ~/.kube/automq-tke-config

export KUBECONFIG=~/.kube/automq-tke-config
kubectl get nodes
```

## Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `alias` | string | `"dev"` | Environment alias, used as naming prefix for all resources |
| `region` | string | `"ap-shanghai"` | Tencent Cloud region |
| `vpc_id` | string | (required) | ID of an existing VPC to deploy into |
| `subnet_ids` | list(string) | (required) | Subnet IDs across different AZs for TKE and VPC-CNI |
| `enable_cluster_internet` | bool | `false` | Enable public internet access for the TKE API server |
| `enable_console` | bool | `false` | Create the AutoMQ console CVM and its dependencies |
| `console_subnet_id` | string | `""` | Subnet ID for the console CVM (required when `enable_console = true`) |
| `console_image_name` | string | `"automq-byoc-console"` | Image name regex filter for the console CVM |
| `console_instance_type` | string | `"SA9.MEDIUM4"` | CVM instance type for the console |
| `console_init` | bool | `false` | Run cloud-init to auto-configure the console on first boot |
| `console_public_access` | bool | `false` | Assign a public EIP to the console (when false, only accessible via private IP) |
| `automq_node_pool` | object | see below | AutoMQ workload node pool configuration |

### automq_node_pool

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `instance_type` | string | `"SA5.LARGE16"` | CVM instance type |
| `min_size` | number | `3` | Auto-scaling minimum |
| `max_size` | number | `5` | Auto-scaling maximum |
| `desired_capacity` | number | `4` | Initial desired node count |
| `instance_charge_type` | string | `"SPOTPAID"` | `SPOTPAID`, `POSTPAID_BY_HOUR`, or `PREPAID` |
| `spot_max_price` | string | `"1000"` | Max bid price (only for `SPOTPAID`) |
| `prepaid_period` | number | `1` | Subscription months: 1–12, 24, 36 (only for `PREPAID`) |
| `prepaid_renew_flag` | string | `"NOTIFY_AND_AUTO_RENEW"` | Auto-renewal policy (only for `PREPAID`) |

## Outputs

### Core

| Output | Description |
|--------|-------------|
| `cloud_provider` | Cloud provider identifier (`tencentcloud`) |
| `cloud_account_id` | Tencent Cloud account ID (owner UIN) |
| `region` | Deployed region |
| `zone` | Primary availability zone (from the first provided subnet) |
| `cluster` | TKE cluster ID |
| `vpc_id` | VPC ID |
| `subnet_ids` | Subnet IDs used for TKE cluster |
| `ops_bucket_name` | COS ops bucket name |
| `data_bucket_name` | COS data bucket name |
| `cluster_security_group` | TKE cluster security group ID |
| `console_dns_zone_id` | Private DNS zone ID |
| `cam_role_name` | CAM role name for node pools |

### Kubernetes Access

| Output | Description |
|--------|-------------|
| `k8s_cluster_auth` | K8s auth info from internet endpoint (sensitive; empty when `enable_cluster_internet = false`) |
| `k8s_cluster_auth_intranet` | K8s auth info from intranet endpoint (sensitive) |
| `kube_config` | Kubeconfig for internet access (sensitive; empty when `enable_cluster_internet = false`) |
| `kube_config_intranet` | Kubeconfig for intranet access (sensitive) |

### Console (only when `enable_console = true`)

| Output | Description |
|--------|-------------|
| `console_endpoint` | Console web URL (public EIP or private IP depending on `console_public_access`) |
| `console_initial_username` | Initial admin username (`admin`) |
| `console_initial_password` | Initial admin password — the CVM instance ID (sensitive) |
| `console_private_key_pem` | SSH private key for the console instance (sensitive) |
| `console_security_group_id` | Console security group ID |
| `console_cam_role_name` | Console CAM role name |

## Clean Up

```bash
terraform destroy
```
