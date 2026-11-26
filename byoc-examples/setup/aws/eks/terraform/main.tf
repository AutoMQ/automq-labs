data "aws_caller_identity" "current" {}

data "aws_eks_cluster_auth" "this" {
  name       = module.eks-env.cluster_name
  depends_on = [module.eks-env]
}

resource "kubernetes_namespace" "automq_console" {
  metadata {
    name = var.automq_console_namespace
  }
}

resource "kubernetes_service_account" "automq_console" {
  metadata {
    name      = var.automq_console_service_account
    namespace = kubernetes_namespace.automq_console.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = var.automq_console_role_arn
    }
  }
}

resource "kubernetes_secret" "automq_console_config" {
  metadata {
    name      = "${var.resource_suffix}-automq-console-config"
    namespace = kubernetes_namespace.automq_console.metadata[0].name
  }

  type = "Opaque"

  data = {
    config = base64encode(var.automq_console_config)
  }
}

resource "aws_eks_access_entry" "console" {
  cluster_name  = module.eks-env.cluster_name
  principal_arn = var.automq_console_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "console" {
  cluster_name  = module.eks-env.cluster_name
  principal_arn = var.automq_console_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.console]
}

resource "helm_release" "automq_console" {
  name              = "${var.resource_suffix}-automq-console"
  namespace         = kubernetes_namespace.automq_console.metadata[0].name
  create_namespace  = false
  repository        = "oci://automq.azurecr.io/helm"
  chart             = "automq-byoc-console-chart"
  version           = var.automq_console_chart_version
  wait              = true
  timeout           = 900
  dependency_update = true

  values = [yamlencode({
    automqByocConsole = {
      config = {
        existingSecret = kubernetes_secret.automq_console_config.metadata[0].name
      }
    }
    aws = {
      account = data.aws_caller_identity.current.account_id
      network = {
        vpcId     = module.eks-env.vpc_id
        subnetIds = slice(module.eks-env.public_subnets, 0, 2)
      }
    }
    serviceAccount = {
      name = kubernetes_service_account.automq_console.metadata[0].name
    }
    persistence = {
      storageClass = var.automq_console_storage_class
    }
    ingress = {
      enabled = true
      host    = var.automq_console_domain_name
      alb = {
        scheme         = "internet-facing"
        protocol       = "HTTPS"
        certificateArn = var.automq_console_acm_certificate_arn
      }
    }
  })]

  depends_on = [
    kubernetes_secret.automq_console_config,
    kubernetes_service_account.automq_console,
    aws_eks_access_policy_association.console
  ]
}

