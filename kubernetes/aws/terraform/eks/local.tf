locals {
  # Random suffix for all resources
  resource_suffix = "${random_string.suffix.result}-${var.resource_suffix}"

  # Cluster name
  cluster_name = "eks-${local.resource_suffix}"

  # IAM roles
  node_group_role_name         = "node-role-${local.resource_suffix}"
  alb_controller_role_name     = "alb-role-${local.resource_suffix}"
  ebs_csi_role_name            = "csi-role-${local.resource_suffix}"
  cluster_autoscaler_role_name = "autoscaler-role-${local.resource_suffix}"

  # Node groups
  system_node_group_name = "sys-${local.resource_suffix}"

  # Helm releases - keeping these simple as they are internal to K8s
  cluster_autoscaler_release_name = "cluster-autoscaler"
  alb_controller_release_name     = "aws-load-balancer-controller"

  # Other configurations
  enable_autoscaler             = true
  enable_alb_ingress_controller = true

  min_worker_nodes = 0
  max_worker_nodes = 50

  min_control_nodes = 1
  max_control_nodes = 10

  vpc_id             = var.vpc_id
  private_subnet_ids = var.subnet_ids
}