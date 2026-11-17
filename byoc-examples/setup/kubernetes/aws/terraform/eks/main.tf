# Data source for current AWS account 
data "aws_caller_identity" "current" {}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.2.0"

  name               = local.cluster_name
  kubernetes_version = var.cluster_options.kubernetes_version
  service_ipv4_cidr  = var.cluster_options.service_ipv4_cidr

  endpoint_private_access                  = var.cluster_options.endpoint_private_access
  endpoint_public_access                   = var.cluster_options.endpoint_public_access
  endpoint_public_access_cidrs             = var.cluster_options.endpoint_public_access_cidrs
  authentication_mode                      = var.cluster_options.authentication_mode
  enable_cluster_creator_admin_permissions = var.cluster_options.enable_cluster_creator_admin_permissions
  enabled_log_types                        = var.cluster_options.enabled_log_types
  cloudwatch_log_group_retention_in_days   = var.cluster_options.log_retention_days
  access_entries = var.cluster_options.deployer_role_arn == null ? {} : {
    deployer = {
      principal_arn = var.cluster_options.deployer_role_arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
  tags = var.tags

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  enable_irsa = true
}

# EKS Managed Node Group - System Nodes
resource "aws_eks_node_group" "system_nodes" {
  cluster_name    = module.eks.cluster_name
  node_group_name = var.system_node_group.name
  node_role_arn   = aws_iam_role.node_group_role.arn

  subnet_ids = coalesce(var.system_node_group.subnet_ids, var.subnet_ids)

  capacity_type  = var.system_node_group.capacity_type
  instance_types = var.system_node_group.instance_types
  ami_type       = var.system_node_group.ami_type
  version        = var.system_node_group.kubernetes_version

  scaling_config {
    desired_size = var.system_node_group.desired_size
    max_size     = var.system_node_group.max_size
    min_size     = var.system_node_group.min_size
  }

  labels = var.system_node_group.labels
  tags   = merge(var.tags, local.autoscaler_discovery_tags)

  dynamic "launch_template" {
    for_each = var.system_node_group.launch_template_key == null ? [] : [var.system_node_group.launch_template_key]
    content {
      id      = aws_launch_template.nodes[launch_template.value].id
      version = aws_launch_template.nodes[launch_template.value].latest_version
    }
  }
  dynamic "update_config" {
    for_each = var.system_node_group.max_unavailable == null ? [] : [var.system_node_group.max_unavailable]
    content { max_unavailable = update_config.value }
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly,
    aws_eks_addon.vpc_cni,
    terraform_data.dependencies,
  ]
}

# IAM Role for EKS Node Group
resource "aws_iam_role" "node_group_role" {
  name = coalesce(var.node_iam.role_name, "${local.resource_suffix}-node-group-role")
  tags = var.tags

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

# Attach required policies to the node group role
resource "aws_iam_role_policy_attachment" "node_group_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEKS_CNI_Policy" {
  count      = var.node_iam.attach_cni_policy ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${var.node_iam.ecr_policy_name}"
  role       = aws_iam_role.node_group_role.name
}

resource "null_resource" "kube_config" {
  count = var.manage_kubeconfig ? 1 : 0
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region ${var.region} --name ${local.cluster_name} --no-verify-ssl"
  }
  depends_on = [
    module.eks
  ]
}

# Call eks-addons module to install cluster addons
module "eks_addons" {
  count  = var.install_addons ? 1 : 0
  source = "../eks-addons"

  region       = var.region
  cluster_name = module.eks.cluster_name

  vpc_id          = var.vpc_id
  resource_suffix = var.resource_suffix

  # Default addon configurations - can be overridden via variables
  enable_vpc_cni                = !var.manage_core_addons
  enable_coredns                = !var.manage_core_addons
  enable_kube_proxy             = !var.manage_core_addons
  enable_pod_identity_agent     = true
  enable_autoscaler             = true
  enable_alb_ingress_controller = true
  enable_ebs_csi_driver         = !var.manage_core_addons

  role_arns = { for name, role in aws_iam_role.pod : name => role.arn }

  providers = {
    aws        = aws
    kubernetes = kubernetes
    helm       = helm
  }

  depends_on = [
    module.eks
  ]
}
