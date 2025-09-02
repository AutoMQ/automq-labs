resource "aws_eks_addon" "vpc_cni" {
  count = var.enable_vpc_cni ? 1 : 0

  cluster_name = local.cluster_name
  addon_name   = "vpc-cni"

  resolve_conflicts_on_update = "OVERWRITE"
  resolve_conflicts_on_create = "OVERWRITE"

  configuration_values = jsonencode({
    "enableNetworkPolicy" : "true"
  })
}

resource "aws_eks_addon" "aws_ebs_csi_driver" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  cluster_name = local.cluster_name
  addon_name   = "aws-ebs-csi-driver"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  service_account_role_arn = module.ebs-csi-irsa-role[0].arn

  preserve   = true
  depends_on = [module.ebs-csi-irsa-role]
}
