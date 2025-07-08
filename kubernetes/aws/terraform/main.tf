# Configure AWS Provider and region
provider "aws" {
  region = local.region
}

# Define local variables for resource naming and node group configuration
locals {
    region = "us-east-1"
    resource_suffix = "automqlab"

    # S3 bucket naming
    ops_bucket_name = "automq-ops-${local.resource_suffix}"    # Bucket for operational data
    data_bucket_name = "automq-data-${local.resource_suffix}"  # Bucket for application data

    # EKS node group configuration
    node_group = {
        name          = "automq-node-group"
        desired_size  = 4                # Desired number of nodes
        max_size      = 10               # Maximum number of nodes
        min_size      = 3                # Minimum number of nodes
        instance_type = "c6g.2xlarge"    # Compute-optimized instance with AWS Graviton2 processor
        ami_type      = "AL2_ARM_64"     # Amazon Linux 2 AMI type, can use AL2_ARM_64 for ARM architecture
    }
}

# Network module: Creates VPC, subnets, and other network resources
module "network" {
    source  = "./network"

    region  = local.region
    resource_suffix = local.resource_suffix
}

# EKS module: Creates and configures the EKS cluster
module "eks" {
    source  = "./eks"

    region  = local.region
    vpc_id  = module.network.vpc_id
    subnet_ids = module.network.private_subnets
    resource_suffix = local.resource_suffix

    resource_depends_on = module.network
}

# Operations bucket: Stores cluster operational data
module "ops_bucket" {
  source        = "terraform-aws-modules/s3-bucket/aws"
  version       = "4.1.2"
  create_bucket = true
  bucket        = local.ops_bucket_name
  force_destroy = true      # Allows deletion of non-empty bucket during destroy

  tags = {
    ManagedBy   = "terraform"
  }
}

# Data bucket: Stores application data
module "data_bucket" {
  source        = "terraform-aws-modules/s3-bucket/aws"
  version       = "4.1.2"
  create_bucket = true
  bucket        = local.data_bucket_name
  force_destroy = true      # Allows deletion of non-empty bucket during destroy

  tags = {
    ManagedBy   = "terraform"
  }
}

# IAM module: Configures required IAM roles and permissions for the cluster
module "cluster-iam" {
  source = "./iam"
  region = local.region
  resource_suffix = "${local.resource_suffix}"
  ops_bucket_name = local.ops_bucket_name
  data_bucket_name = local.data_bucket_name
}

# EKS Node Group: Configure worker nodes
resource "aws_eks_node_group" "automq-node-groups" {
  cluster_name    = module.eks.eks_cluster_name
  node_group_name = local.node_group.name
  node_role_arn   = module.cluster-iam.node_group_role_arn

  # Optional: Use multi-AZ configuration
  # subnet_ids = module.eks-env.private_subnets

  # Current config: Use single AZ to reduce costs
  subnet_ids = slice(module.network.private_subnets, 0, 1)

  ami_type       = local.node_group.ami_type
  capacity_type  = "ON_DEMAND"           # Use On-Demand instances, can switch to "SPOT" for cost savings
  instance_types = [local.node_group.instance_type]

  # Node group auto-scaling configuration
  scaling_config {
    desired_size = local.node_group.desired_size
    max_size     = local.node_group.max_size
    min_size     = local.node_group.min_size
  }

  # Node taints: Ensures only specific pods are scheduled to these nodes
  taint {
    key = "dedicated"
    value = "automq"
    effect = "NO_SCHEDULE"
  }

  labels = {}

  depends_on = [
    module.network,
    module.eks,
    module.cluster-iam
  ]
}

# Output important configuration values
output "region" {
    description = "AWS region"
    value       = local.region
}

output "vpc_id" {
    description = "VPC ID"
    value       = module.network.vpc_id
}

output "cluster_name" {
    description = "EKS Cluster Name"
    value       = module.eks.eks_cluster_name
}
