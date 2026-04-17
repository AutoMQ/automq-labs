# AutoMQ on Tencent Cloud

This directory contains Terraform configurations for deploying AutoMQ on Tencent Cloud.

## Subdirectories

### [`automq-deploy-env/`](./automq-deploy-env/)

The main Terraform configuration for deploying a complete AutoMQ environment on Tencent Cloud. It provisions:

- A TKE (Tencent Kubernetes Engine) managed cluster in VPC-CNI mode, deployed into an existing VPC and subnets.
- A system node pool (Spot) for cluster components.
- An AutoMQ workload node pool with dedicated taint (`dedicated=automq:NoSchedule`), supporting Spot, on-demand, and monthly subscription (prepaid) billing modes.
- COS buckets for ops and data storage, with bucket policy for cross-account access.
- CAM role and policy for node pool access to COS.
- A Private DNS zone for the AutoMQ console.

## Prerequisites

- Terraform >= 1.3
- Tencent Cloud account with appropriate permissions
- Tencent Cloud credentials configured (e.g., `TENCENTCLOUD_SECRET_ID` and `TENCENTCLOUD_SECRET_KEY` environment variables)
- An existing VPC with subnets across multiple availability zones

## Quick Start

1. Copy the example variables file and fill in your values:

```bash
cd automq-deploy-env
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` according to the comments in the file. See [`terraform.tfvars.example`](./automq-deploy-env/terraform.tfvars.example) for a full reference of all available parameters, including node pool billing mode configuration (Spot / on-demand / monthly subscription).

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

## Outputs

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
| `k8s_cluster_auth` | K8s auth info from internet endpoint (sensitive, empty when public access is disabled) |
| `k8s_cluster_auth_intranet` | K8s auth info from intranet endpoint (sensitive) |
| `kube_config` | Kubeconfig for internet access (sensitive, empty when public access is disabled) |
| `kube_config_intranet` | Kubeconfig for intranet access (sensitive) |

## Deploy AutoMQ Console

After the infrastructure is provisioned, deploy the AutoMQ Console from the [Tencent Cloud Marketplace](https://market.cloud.tencent.com/). Place the Console instance in a subnet within the provided VPC.

Once the Console is running, create a **Deploy Profile** using the Terraform outputs to connect the Console to the provisioned infrastructure.

## Clean Up

```bash
terraform destroy
```
