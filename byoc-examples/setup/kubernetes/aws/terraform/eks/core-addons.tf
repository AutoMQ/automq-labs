data "aws_eks_addon_version" "this" {
  for_each           = var.manage_core_addons ? toset(["vpc-cni", "coredns", "kube-proxy", "aws-ebs-csi-driver"]) : toset([])
  addon_name         = each.key
  kubernetes_version = var.cluster_options.kubernetes_version
  most_recent        = true
}

resource "aws_eks_addon" "vpc_cni" {
  count                       = var.manage_core_addons ? 1 : 0
  cluster_name                = module.eks.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = lookup(var.addon_versions, "vpc-cni", data.aws_eks_addon_version.this["vpc-cni"].version)
  service_account_role_arn    = aws_iam_role.pod["cni"].arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_iam_role_policy_attachment.component]
}

resource "aws_eks_addon" "after_nodes" {
  for_each                    = var.manage_core_addons ? toset(["coredns", "kube-proxy", "aws-ebs-csi-driver"]) : toset([])
  cluster_name                = module.eks.cluster_name
  addon_name                  = each.key
  addon_version               = lookup(var.addon_versions, each.key, data.aws_eks_addon_version.this[each.key].version)
  service_account_role_arn    = each.key == "aws-ebs-csi-driver" ? aws_iam_role.pod["ebs-csi"].arn : null
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.system_nodes, aws_iam_role_policy_attachment.component]
}
