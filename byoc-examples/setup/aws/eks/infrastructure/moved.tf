# Preserve resources from the earlier, standalone Helm Console example.
# These moves do not migrate state from the retired VM Console example.

moved {
  from = module.eks
  to   = module.eks_cluster.module.eks
}

moved {
  from = aws_iam_role.node
  to   = module.eks_cluster.aws_iam_role.node_group_role
}

moved {
  from = aws_iam_role_policy_attachment.node["AmazonEKSWorkerNodePolicy"]
  to   = module.eks_cluster.aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy
}

moved {
  from = aws_iam_role_policy_attachment.node["AmazonEC2ContainerRegistryPullOnly"]
  to   = module.eks_cluster.aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly
}

moved {
  from = aws_launch_template.nodes
  to   = module.eks_cluster.aws_launch_template.nodes
}

moved {
  from = aws_eks_node_group.system
  to   = module.eks_cluster.aws_eks_node_group.system_nodes
}

moved {
  from = aws_eks_node_group.automq
  to   = module.eks_cluster.aws_eks_node_group.workload
}

moved {
  from = aws_autoscaling_group_tag.autoscaler
  to   = module.eks_cluster.aws_autoscaling_group_tag.autoscaler
}

moved {
  from = aws_iam_role_policy_attachment.component
  to   = module.eks_cluster.aws_iam_role_policy_attachment.component
}

moved {
  from = aws_iam_role_policy.autoscaler
  to   = module.eks_cluster.aws_iam_role_policy.autoscaler[0]
}

moved {
  from = aws_iam_role_policy.lb_controller
  to   = module.eks_cluster.aws_iam_role_policy.lb_controller[0]
}

moved {
  from = aws_eks_addon.vpc_cni
  to   = module.eks_cluster.aws_eks_addon.vpc_cni[0]
}

moved {
  from = aws_eks_addon.after_nodes
  to   = module.eks_cluster.aws_eks_addon.after_nodes
}

moved {
  from = aws_iam_role.pod["cni"]
  to   = module.eks_cluster.aws_iam_role.pod["cni"]
}

moved {
  from = aws_iam_role.pod["ebs-csi"]
  to   = module.eks_cluster.aws_iam_role.pod["ebs-csi"]
}

moved {
  from = aws_iam_role.pod["autoscaler"]
  to   = module.eks_cluster.aws_iam_role.pod["autoscaler"]
}

moved {
  from = aws_iam_role.pod["lb-controller"]
  to   = module.eks_cluster.aws_iam_role.pod["lb-controller"]
}
