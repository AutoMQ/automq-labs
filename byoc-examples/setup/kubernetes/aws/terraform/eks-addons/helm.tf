###############################################################################
# Cluster Autoscaler
###############################################################################
resource "helm_release" "autoscaler" {
  count = var.enable_autoscaler ? 1 : 0

  name       = local.cluster_autoscaler_release_name
  namespace  = "kube-system"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = var.autoscaler_chart_version

  dependency_update = true
  values = concat([
    templatefile(
      "${path.module}/templates/cluster-autoscaler-chart-values.yaml.tpl",
      {
        region       = var.region,
        svc_account  = local.cluster_autoscaler_service_account
        cluster_name = local.cluster_name,
        role_arn     = local.cluster_autoscaler_role_arn
      }
    )
  ], var.autoscaler_values)

  # Keep Cluster Autoscaler on the same minor version as the EKS control plane.
  # Chart 9.59.0 defaults to v1.35.0 while the v1.36 image is already released.
  set {
    name  = "image.tag"
    value = var.autoscaler_image_tag
  }

  timeout = 600

  depends_on = [module.cluster_autoscaler_irsa_role]
}

###############################################################################
# ALB Ingress Controller
###############################################################################
resource "helm_release" "alb_controller" {
  count = var.enable_alb_ingress_controller ? 1 : 0

  name       = local.alb_controller_release_name
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lb_controller_chart_version
  namespace  = "kube-system"
  atomic     = true
  timeout    = 900

  dependency_update = true
  values = concat([
    yamlencode({
      "clusterName" : local.cluster_name,
      "serviceAccount" : merge({
        "create" : !var.manage_lb_service_account,
        "name" : local.lb_service_account
        }, var.manage_lb_service_account ? {} : {
        "annotations" : { "eks.amazonaws.com/role-arn" = local.alb_controller_role_arn }
      }),
      "region" : var.region,
      "vpcId" : var.vpc_id,
      "hostNetwork" : var.lb_controller_host_network
    })
  ], var.lb_controller_values)

  depends_on = [
    module.lb_irsa_role,
    kubernetes_service_account.lb_controller_sa
  ]
}

resource "helm_release" "external_dns" {
  count     = var.enable_external_dns ? 1 : 0
  namespace = "kube-system"
  wait      = true
  timeout   = 600

  name = "external-dns"

  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.12.1"


  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.cluster_exteranl_dns_irsa_role[0].arn
  }
  depends_on = [
    module.cluster_exteranl_dns_irsa_role
  ]
}
