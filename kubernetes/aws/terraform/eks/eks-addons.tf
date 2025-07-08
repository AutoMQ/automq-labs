resource "aws_eks_addon" "vpc_cni" {
  cluster_name = module.eks.cluster_name
  addon_name   = "vpc-cni"

  resolve_conflicts_on_update = "OVERWRITE"
  resolve_conflicts_on_create = "OVERWRITE"

  # Get configuration fields: `aws eks describe-addon-configuration --addon-name vpc-cni --addon-version`
  # jq .configurationSchema --raw-output | jq .definitions
  # Note: it seems to miss some ENV VARs presents / supported on the plugin: CF https://github.com/aws/amazon-vpc-cni-k8s
  configuration_values = jsonencode({
    "enableNetworkPolicy": "true"
  })
}

resource "aws_eks_addon" "aws_ebs_csi_driver" {
  cluster_name  = module.eks.cluster_name
  addon_name    = "aws-ebs-csi-driver"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  service_account_role_arn = module.ebs-csi-irsa-role.iam_role_arn

  preserve = true
  depends_on = [module.ebs-csi-irsa-role, aws_eks_node_group.system-nodes]
}
