# Configure AWS Provider and region
provider "aws" {
  region = local.region
}

# Validation: If using existing VPC, ensure required variables are provided
locals {
  validation_check = var.use_existing_vpc && (var.existing_vpc_id == "" || length(var.existing_private_subnet_ids) == 0) ? tobool("Error: When use_existing_vpc is true, existing_vpc_id and existing_private_subnet_ids must be provided") : true

  # Validation: If creating NAT Gateway for existing VPC, public subnets must be provided
  nat_gateway_validation = var.use_existing_vpc && var.create_nat_gateway && length(var.existing_public_subnet_ids) == 0 ? tobool("Error: When use_existing_vpc is true and create_nat_gateway is true, existing_public_subnet_ids must be provided") : true
}

# Define local variables for resource naming and node group configuration
locals {
  region          = var.region
  resource_suffix = var.resource_suffix

  # EKS node group configuration
  node_group = var.node_group
}

# Network module: Creates VPC, subnets, and other network resources
module "network" {
  source = "./network"

  region                      = local.region
  resource_suffix             = local.resource_suffix
  use_existing_vpc            = var.use_existing_vpc
  existing_vpc_id             = var.existing_vpc_id
  existing_private_subnet_ids = var.existing_private_subnet_ids
  existing_public_subnet_ids  = var.existing_public_subnet_ids
  create_nat_gateway          = var.create_nat_gateway
}

# EKS module: Creates and configures the EKS cluster
module "eks" {
  source = "./eks"

  region          = local.region
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.private_subnets
  resource_suffix = local.resource_suffix

  resource_depends_on = module.network
}

# IAM module: Configures required IAM roles and permissions for the cluster
module "cluster-iam" {
  source           = "./iam"
  region           = local.region
  resource_suffix  = local.resource_suffix
  ops_bucket_name  = "*"
  data_bucket_name = "*"
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
  capacity_type  = "SPOT" # Use On-Demand instances, can switch to "SPOT" for cost savings
  instance_types = [local.node_group.instance_type]

  # Node group auto-scaling configuration
  scaling_config {
    desired_size = local.node_group.desired_size
    max_size     = local.node_group.max_size
    min_size     = local.node_group.min_size
  }

  # Node taints: Ensures only specific pods are scheduled to these nodes
  #   taint {
  #     key    = "dedicated"
  #     value  = "automq"
  #     effect = "NO_SCHEDULE"
  #   }

  labels = {}

  # Lifecycle configuration: Ignore changes to desired_size to prevent conflicts with cluster autoscaler
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [
    module.network,
    module.eks,
    module.cluster-iam
  ]
}
