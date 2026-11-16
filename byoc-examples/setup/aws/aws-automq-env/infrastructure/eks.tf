module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.2.0"

  name               = local.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = var.vpc_id
  subnet_ids         = local.private_subnets
  service_ipv4_cidr  = var.service_ipv4_cidr

  endpoint_private_access                  = true
  endpoint_public_access                   = length(var.public_api_allowed_cidrs) > 0
  endpoint_public_access_cidrs             = var.public_api_allowed_cidrs
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  enable_irsa                              = true
  enabled_log_types                        = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days   = 7

  # This is the independent Terraform/Helm deployment role, never the Console Role.
  access_entries = {
    deployer = {
      principal_arn = var.deployer_role_arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
  tags       = local.tags
  depends_on = [terraform_data.network_contract, terraform_data.egress_contract]
}

resource "aws_iam_role" "node" {
  name = "${var.name_prefix}-node"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
  tags = local.tags
}

# No S3, Route53, CNI, CSI, autoscaler, or AutoMQ business policies attach to Node.
resource "aws_iam_role_policy_attachment" "node" {
  for_each   = toset(["AmazonEKSWorkerNodePolicy", "AmazonEC2ContainerRegistryPullOnly"])
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}

resource "aws_launch_template" "nodes" {
  for_each               = toset(["system", "automq"])
  name_prefix            = "${var.name_prefix}-${each.key}-"
  update_default_version = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 40
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }
  tags = local.tags
}

resource "aws_eks_node_group" "system" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "${var.name_prefix}-system"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = local.private_subnets
  capacity_type   = "ON_DEMAND"
  instance_types  = [var.system_instance_type]
  ami_type        = "AL2023_x86_64_STANDARD"
  version         = var.kubernetes_version
  labels          = { "automq.io/pool" = "system" }
  scaling_config {
    min_size     = 2
    desired_size = 2
    max_size     = var.system_max_nodes
  }
  update_config { max_unavailable = 1 }
  launch_template {
    id      = aws_launch_template.nodes["system"].id
    version = aws_launch_template.nodes["system"].latest_version
  }
  tags = merge(local.tags, {
    "k8s.io/cluster-autoscaler/enabled"               = "true"
    "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
  })
  lifecycle { ignore_changes = [scaling_config[0].desired_size] }
  depends_on = [aws_iam_role_policy_attachment.node, aws_eks_addon.vpc_cni, aws_route.private_nat]
}

resource "aws_eks_node_group" "automq" {
  for_each        = var.private_subnet_ids_by_az
  cluster_name    = module.eks.cluster_name
  node_group_name = "${var.name_prefix}-automq-${each.key}"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = [each.value]
  capacity_type   = "ON_DEMAND"
  instance_types  = [var.automq_instance_type]
  ami_type        = "AL2023_ARM_64_STANDARD"
  version         = var.kubernetes_version
  labels          = local.automq_selector
  taint {
    key    = "dedicated"
    value  = "automq"
    effect = "NO_SCHEDULE"
  }
  scaling_config {
    min_size     = 1
    desired_size = 1
    max_size     = var.automq_max_nodes_per_az
  }
  update_config { max_unavailable = 1 }
  launch_template {
    id      = aws_launch_template.nodes["automq"].id
    version = aws_launch_template.nodes["automq"].latest_version
  }
  tags = merge(local.tags, {
    "k8s.io/cluster-autoscaler/enabled"                            = "true"
    "k8s.io/cluster-autoscaler/${local.cluster_name}"              = "owned"
    "k8s.io/cluster-autoscaler/node-template/label/automq.io/pool" = "automq"
    "k8s.io/cluster-autoscaler/node-template/taint/dedicated"      = "automq:NoSchedule"
  })
  lifecycle { ignore_changes = [scaling_config[0].desired_size] }
  depends_on = [aws_iam_role_policy_attachment.node, aws_eks_addon.vpc_cni, aws_route.private_nat]
}

locals {
  autoscaling_group_names = merge(
    { system = aws_eks_node_group.system.resources[0].autoscaling_groups[0].name },
    { for az, group in aws_eks_node_group.automq : az => group.resources[0].autoscaling_groups[0].name },
  )
  autoscaling_group_tags = merge([for name, group in local.autoscaling_group_names : {
    for key, value in merge({
      "k8s.io/cluster-autoscaler/enabled"               = "true"
      "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
      }, name == "system" ? {} : {
      "k8s.io/cluster-autoscaler/node-template/label/automq.io/pool" = "automq"
      "k8s.io/cluster-autoscaler/node-template/taint/dedicated"      = "automq:NoSchedule"
    }) : "${name}:${key}" => { name = group, key = key, value = value }
  }]...)
}

# EKS node-group tags are not propagated to the underlying Auto Scaling Group.
# Discovery and the autoscaler IAM conditions both require these ASG tags.
resource "aws_autoscaling_group_tag" "autoscaler" {
  for_each               = local.autoscaling_group_tags
  autoscaling_group_name = each.value.name
  tag {
    key                 = each.value.key
    value               = each.value.value
    propagate_at_launch = false
  }
}

data "aws_eks_addon_version" "this" {
  for_each           = toset(["vpc-cni", "coredns", "kube-proxy", "aws-ebs-csi-driver"])
  addon_name         = each.key
  kubernetes_version = var.kubernetes_version
  most_recent        = true
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = lookup(var.addon_versions, "vpc-cni", data.aws_eks_addon_version.this["vpc-cni"].version)
  service_account_role_arn    = aws_iam_role.pod["cni"].arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_iam_role_policy_attachment.component]
}

resource "aws_eks_addon" "after_nodes" {
  for_each                    = toset(["coredns", "kube-proxy", "aws-ebs-csi-driver"])
  cluster_name                = module.eks.cluster_name
  addon_name                  = each.key
  addon_version               = lookup(var.addon_versions, each.key, data.aws_eks_addon_version.this[each.key].version)
  service_account_role_arn    = each.key == "aws-ebs-csi-driver" ? aws_iam_role.pod["ebs-csi"].arn : null
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.system, aws_iam_role_policy_attachment.component]
}
