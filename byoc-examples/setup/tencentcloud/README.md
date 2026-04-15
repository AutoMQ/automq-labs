# AutoMQ on Tencent Cloud

This directory contains Terraform configurations for deploying AutoMQ on Tencent Cloud.

## Subdirectories

### [`automq-deploy-env/`](./automq-deploy-env/)

The main Terraform configuration for deploying a complete AutoMQ environment on Tencent Cloud. It provisions:

- A VPC with public and private subnets across multiple availability zones.
- A NAT Gateway for private subnet outbound access.
- A TKE (Tencent Kubernetes Engine) managed cluster in VPC-CNI mode.
- A system node pool (Spot) for cluster components.
- An AutoMQ workload node pool with dedicated taint (`dedicated=automq:NoSchedule`).
- COS buckets for ops and data storage.
- CAM role and policy for node pool access to COS.
- A Private DNS zone for the AutoMQ console.

## Prerequisites

- Terraform >= 1.3
- Tencent Cloud account with appropriate permissions
- Tencent Cloud credentials configured (e.g., `TENCENTCLOUD_SECRET_ID` and `TENCENTCLOUD_SECRET_KEY` environment variables)

## Quick Start

1. Create a `terraform.tfvars` file in the `automq-deploy-env/` directory:

```hcl
alias  = "dev"
region = "ap-shanghai"

# Optional: specify availability zones explicitly
# availability_zones = ["ap-shanghai-2", "ap-shanghai-4", "ap-shanghai-5"]

# Optional: customize the AutoMQ workload node pool
# automq_node_pool = {
#   instance_type    = "SA5.LARGE16"
#   min_size         = 3
#   max_size         = 5
#   desired_capacity = 4
#   spot             = true
#   spot_max_price   = "1000"
# }
```

2. Deploy:

```bash
cd automq-deploy-env
terraform init
terraform plan
terraform apply
```

3. Get the kubeconfig:

```bash
terraform output -raw kube_config > ~/.kube/automq-tke-config
export KUBECONFIG=~/.kube/automq-tke-config
kubectl get nodes
```

## Outputs

| Output | Description |
|--------|-------------|
| `cloud_provider` | Cloud provider identifier (`tencentcloud`) |
| `scope` | Current account main UIN |
| `region` | Deployed region |
| `zone` | Primary availability zone |
| `cluster` | TKE cluster ID |
| `vpc_id` | VPC ID |
| `console_subnet_id` | Public subnet ID for console placement |
| `automq_subnet_map` | Map of availability zones to private subnet IDs |
| `ops_bucket_name` | COS ops bucket name |
| `data_bucket_name` | COS data bucket name |
| `cluster_security_group` | TKE cluster security group ID |
| `console_dns_zone_id` | Private DNS zone ID |
| `cam_role_name` | CAM role name for node pools |
| `k8s_cluster_auth` | K8s auth info from internet endpoint (sensitive) |
| `k8s_cluster_auth_intranet` | K8s auth info from intranet endpoint (sensitive) |
| `kube_config` | Kubeconfig for internet access (sensitive) |
| `kube_config_intranet` | Kubeconfig for intranet access (sensitive) |

## Deploy AutoMQ Console

After the infrastructure is provisioned, deploy the AutoMQ Console from the [Tencent Cloud Marketplace](https://market.cloud.tencent.com/). Place the Console instance in the public subnet within the created VPC.

Once the Console is running, create a **Deploy Profile** using the Terraform outputs to connect the Console to the provisioned infrastructure.

## Clean Up

```bash
terraform destroy
```
