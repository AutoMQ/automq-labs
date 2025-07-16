locals {
  # Random suffix for all resources
  resource_suffix = "${random_string.suffix.result}-${var.resource_suffix}"

  # Cluster name
  cluster_name = "eks-${local.resource_suffix}"

  # IAM roles
  node_group_role_name = "node-role-${local.resource_suffix}"

  # Node groups
  system_node_group_name = "sys-${local.resource_suffix}"

  # Other configurations
  min_worker_nodes = 0
  max_worker_nodes = 50

  min_control_nodes = 1
  max_control_nodes = 10

  vpc_id             = var.vpc_id
  private_subnet_ids = var.subnet_ids
}