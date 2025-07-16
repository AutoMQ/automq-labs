data "aws_eks_cluster" "eks_cluster" {
  name = var.cluster_name
}

# Get OIDC issuer URL from the EKS cluster
data "aws_iam_openid_connect_provider" "eks_oidc" {
  url = data.aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

locals {
  cluster_endpoint       = data.aws_eks_cluster.eks_cluster.endpoint
  cluster_ca_certificate = data.aws_eks_cluster.eks_cluster.certificate_authority[0].data
  cluster_name           = data.aws_eks_cluster.eks_cluster.name
  oidc_provider_arn      = data.aws_iam_openid_connect_provider.eks_oidc.arn

  # Service account names
  lb_service_account                 = "aws-load-balancer-controller"
  ebs_csi_service_account            = "ebs-csi-controller-sa"
  cluster_autoscaler_service_account = "cluster-autoscaler"

  # IAM role names
  alb_controller_role_name     = "alb-role-${var.resource_suffix}"
  ebs_csi_role_name            = "csi-role-${var.resource_suffix}"
  cluster_autoscaler_role_name = "autoscaler-role-${var.resource_suffix}"

  # Helm release names
  cluster_autoscaler_release_name = "cluster-autoscaler"
  alb_controller_release_name     = "aws-load-balancer-controller"
}
