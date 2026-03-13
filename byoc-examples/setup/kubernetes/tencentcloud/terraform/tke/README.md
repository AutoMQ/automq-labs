# AutoMQ on TKE (Tencent Kubernetes Engine)

This Terraform module provisions a managed TKE cluster on Tencent Cloud with dedicated node pools and CAM permissions required by AutoMQ.

## Architecture Overview

The module creates the following resources:

- Managed TKE cluster (VPC-CNI networking)
- Public node pool (auto-scaling, minimum 2 nodes)
- AutoMQ dedicated node pool (user-specified instance type, 3 nodes, with `dedicated=automq` taint)
- CAM role and policy (granting COS and CVM permissions to nodes)
- Cluster intranet API Server endpoint

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- A Tencent Cloud account with API credentials (SecretId / SecretKey)
- An existing VPC and subnets
- An existing SSH key pair and security group

## Quick Start

### 1. Configure Authentication

Set your Tencent Cloud API credentials via environment variables:

```bash
export TENCENTCLOUD_SECRET_ID="your-secret-id"
export TENCENTCLOUD_SECRET_KEY="your-secret-key"
```

### 2. Configure Variables

Create your variable file from the provided example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and fill in the actual resource IDs for your environment.

### 3. Initialize and Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 4. Retrieve Kubeconfig

After deployment, retrieve the kubeconfig from the [TKE console](https://console.cloud.tencent.com/tke2/cluster) or via the Tencent Cloud CLI.

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `region` | Tencent Cloud region (e.g. `ap-guangzhou`) | `string` | — | Yes |
| `vpc_id` | ID of an existing VPC | `string` | — | Yes |
| `availability_zones` | List of availability zones. Must provide 1 or 3. | `list(string)` | — | Yes |
| `subnet_ids` | List of subnet IDs corresponding to the availability zones. Must provide 1 or 3. | `list(string)` | — | Yes |
| `tke_cluster_name` | Name of the TKE cluster | `string` | — | Yes |
| `key_ids` | List of SSH key IDs for node pool instances | `list(string)` | — | Yes |
| `security_group_ids` | List of security group IDs for node pool instances | `list(string)` | — | Yes |
| `tke_cluster_version` | Kubernetes version | `string` | `1.32.2` | No |
| `node_os` | OS image ID for node pool instances | `string` | `img-eb30mz89` | No |
| `public_instance_type` | Instance type for the public node pool | `string` | `SA9.MEDIUM4` | No |
| `instance_type` | Instance type for the AutoMQ dedicated node pool | `string` | `SA5.LARGE16` | No |
| `instance_charge_type` | Billing mode: `POSTPAID_BY_HOUR` (on-demand) or `SPOTPAID` (spot) | `string` | `POSTPAID_BY_HOUR` | No |
| `spot_max_price` | Max price for spot instances (only effective when `SPOTPAID`) | `string` | `1000` | No |
| `service_cidr` | Service CIDR for the TKE cluster | `string` | `192.168.128.0/20` | No |
| `cam_policy_file` | Path to the CAM policy JSON file | `string` | `cam-policy.json` | No |
| `common_tags` | Additional tags to apply to resources | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| `tke_cluster_id` | The ID of the TKE cluster |
| `cam_role_name` | CAM role name bound to the AutoMQ node pool |

## Cleanup

```bash
terraform destroy
```
