# EKS and its shared IAM OIDC provider belong to the external cluster owner.
data "aws_eks_cluster" "target" {
  name = var.kubernetes_cluster_id
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.target.identity[0].oidc[0].issuer
}

locals {
  eks_oidc_issuer = trimprefix(data.aws_eks_cluster.target.identity[0].oidc[0].issuer, "https://")
}

resource "kubernetes_namespace_v1" "connect" {
  depends_on = [terraform_data.preflight]

  metadata {
    name = var.connect_namespace
    labels = {
      "app.kubernetes.io/part-of" = "automq-connect"
    }
  }
}

resource "kubernetes_service_account_v1" "connect" {
  metadata {
    name      = var.connect_service_account
    namespace = kubernetes_namespace_v1.connect.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn"               = aws_iam_role.connect_worker.arn
      "eks.amazonaws.com/sts-regional-endpoints" = "true"
    }
  }

  automount_service_account_token = true
}
