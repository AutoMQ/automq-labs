
# -----------------------------------------------------------------------------
# AutoMQ EKS Existing Cluster Configuration
# -----------------------------------------------------------------------------

# Local values for consistent resource naming and configuration
locals {
  region          = var.region
  resource_suffix = var.resource_suffix
  node_group      = var.node_group
}

# AutoMQ BYOC (Bring Your Own Cloud) Environment
# This module sets up the AutoMQ console and required infrastructure
module "automq-byoc" {
  source  = "AutoMQ/automq-byoc-environment/aws"
  version = "0.3.1"

  cloud_provider_region = var.region
  automq_byoc_env_id    = var.resource_suffix

  # Use existing VPC and subnet
  create_new_vpc                           = false
  automq_byoc_vpc_id                       = var.vpc_id
  automq_byoc_env_console_public_subnet_id = var.console_subnet_id
}

