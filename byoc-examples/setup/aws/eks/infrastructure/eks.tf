# Reuse the shared EKS implementation used by Playground. This example selects
# its three-AZ, Pod-identity configuration explicitly; shared defaults stay intact.
module "eks_cluster" {
  source = "../../../kubernetes/aws/terraform/eks"

  region          = local.region
  resource_suffix = var.name_prefix
  cluster_name    = local.cluster_name
  vpc_id          = terraform_data.network_contract.input.vpc_id
  subnet_ids      = local.private_subnets
  tags            = local.tags

  cluster_options = {
    kubernetes_version                       = var.kubernetes_version
    service_ipv4_cidr                        = var.service_ipv4_cidr
    endpoint_private_access                  = true
    endpoint_public_access                   = length(var.public_api_allowed_cidrs) > 0
    endpoint_public_access_cidrs             = var.public_api_allowed_cidrs
    authentication_mode                      = "API"
    enable_cluster_creator_admin_permissions = false
    deployer_role_arn                        = var.deployer_role_arn
    enabled_log_types                        = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
    log_retention_days                       = 7
  }

  node_iam = {
    role_name         = "${var.name_prefix}-node"
    attach_cni_policy = false
    ecr_policy_name   = "AmazonEC2ContainerRegistryPullOnly"
  }
  node_launch_templates = {
    for pool in ["system", "automq"] : pool => {
      name_prefix           = "${var.name_prefix}-${pool}-"
      root_volume_size      = 40
      root_volume_encrypted = true
      metadata_hop_limit    = 1
    }
  }
  system_node_group = {
    name                = "${var.name_prefix}-system"
    instance_types      = [var.system_instance_type]
    capacity_type       = "ON_DEMAND"
    ami_type            = "AL2023_x86_64_STANDARD"
    kubernetes_version  = var.kubernetes_version
    labels              = { "automq.io/pool" = "system" }
    min_size            = 2
    desired_size        = 2
    max_size            = var.system_max_nodes
    launch_template_key = "system"
    max_unavailable     = 1
  }
  workload_node_groups = {
    for az, subnet in var.private_subnet_ids_by_az : az => {
      name                = "${var.name_prefix}-automq-${az}"
      subnet_ids          = [subnet]
      instance_types      = [var.automq_instance_type]
      capacity_type       = "ON_DEMAND"
      ami_type            = "AL2023_ARM_64_STANDARD"
      kubernetes_version  = var.kubernetes_version
      labels              = local.automq_selector
      taints              = [{ key = "dedicated", value = "automq", effect = "NO_SCHEDULE" }]
      min_size            = 1
      desired_size        = 1
      max_size            = var.automq_max_nodes_per_az
      launch_template_key = "automq"
      max_unavailable     = 1
    }
  }
  component_irsa_prefix       = var.name_prefix
  manage_core_addons          = true
  addon_versions              = var.addon_versions
  enable_autoscaler_discovery = true
  install_addons              = false
  manage_kubeconfig           = false
  resource_depends_on = {
    egress_contract = terraform_data.egress_contract.id
    nat_routes      = { for table, route in aws_route.private_nat : table => route.id }
  }
}

# Console is an AutoMQ environment identity, separate from shared EKS components.
# Its OIDC-dependent role must be ready before adding this Access Entry.
resource "aws_eks_access_entry" "console" {
  cluster_name  = module.eks_cluster.eks_cluster_name
  principal_arn = aws_iam_role.pod["console"].arn
  type          = "STANDARD"
  tags          = local.tags
}

resource "aws_eks_access_policy_association" "console" {
  cluster_name  = module.eks_cluster.eks_cluster_name
  principal_arn = aws_eks_access_entry.console.principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}
