# Preserve existing callers when making previously mandatory actions optional.
moved {
  from = aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy
  to   = aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy[0]
}
moved {
  from = null_resource.kube_config
  to   = null_resource.kube_config[0]
}
moved {
  from = module.eks_addons
  to   = module.eks_addons[0]
}
