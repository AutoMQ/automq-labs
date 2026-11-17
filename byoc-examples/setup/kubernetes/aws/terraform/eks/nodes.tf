# Explicit dependencies let callers wait for shared routes/network validation
# without adding depends_on to this module's legacy provider configuration.
resource "terraform_data" "dependencies" {
  count = var.resource_depends_on == null ? 0 : 1
  input = var.resource_depends_on
}

resource "aws_launch_template" "nodes" {
  for_each               = var.node_launch_templates
  name_prefix            = each.value.name_prefix
  update_default_version = true
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = each.value.metadata_hop_limit
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = each.value.root_volume_size
      volume_type           = "gp3"
      encrypted             = each.value.root_volume_encrypted
      delete_on_termination = true
    }
  }
  tags = var.tags
}

resource "aws_eks_node_group" "workload" {
  for_each        = var.workload_node_groups
  cluster_name    = module.eks.cluster_name
  node_group_name = each.value.name
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = each.value.subnet_ids
  capacity_type   = each.value.capacity_type
  instance_types  = each.value.instance_types
  ami_type        = each.value.ami_type
  version         = each.value.kubernetes_version
  labels          = each.value.labels
  tags            = merge(var.tags, local.autoscaler_discovery_tags, local.workload_template_tags[each.key])
  scaling_config {
    min_size     = each.value.min_size
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
  }
  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }
  update_config { max_unavailable = each.value.max_unavailable }
  dynamic "launch_template" {
    for_each = each.value.launch_template_key == null ? [] : [each.value.launch_template_key]
    content {
      id      = aws_launch_template.nodes[launch_template.value].id
      version = aws_launch_template.nodes[launch_template.value].latest_version
    }
  }
  lifecycle { ignore_changes = [scaling_config[0].desired_size] }
  depends_on = [
    aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly,
    aws_eks_addon.vpc_cni,
    terraform_data.dependencies,
  ]
}

locals {
  autoscaler_discovery_tags = var.enable_autoscaler_discovery ? {
    "k8s.io/cluster-autoscaler/enabled"               = "true"
    "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
  } : {}
  workload_template_tags = { for key, pool in var.workload_node_groups : key => var.enable_autoscaler_discovery ? merge(
    { for label, value in pool.labels : "k8s.io/cluster-autoscaler/node-template/label/${label}" => value },
    { for taint in pool.taints : "k8s.io/cluster-autoscaler/node-template/taint/${taint.key}" => "${taint.value}:${taint.effect == "NO_SCHEDULE" ? "NoSchedule" : taint.effect == "NO_EXECUTE" ? "NoExecute" : "PreferNoSchedule"}" }
  ) : {} }
  autoscaling_group_names = merge(
    { system = aws_eks_node_group.system_nodes.resources[0].autoscaling_groups[0].name },
    { for key, pool in aws_eks_node_group.workload : key => pool.resources[0].autoscaling_groups[0].name },
  )
  autoscaling_group_tags = var.enable_autoscaler_discovery ? merge([for key, name in local.autoscaling_group_names : {
    for tag, value in merge(local.autoscaler_discovery_tags, lookup(local.workload_template_tags, key, {})) :
    "${key}:${tag}" => { name = name, key = tag, value = value }
  }]...) : {}
}

# Managed node-group tags do not propagate to their underlying ASGs.
resource "aws_autoscaling_group_tag" "autoscaler" {
  for_each               = local.autoscaling_group_tags
  autoscaling_group_name = each.value.name
  tag {
    key                 = each.value.key
    value               = each.value.value
    propagate_at_launch = false
  }
}
