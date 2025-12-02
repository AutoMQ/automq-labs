###############################################################################
# Cluster Autoscaler
###############################################################################
resource "helm_release" "autoscaler" {
  count = var.enable_autoscaler ? 1 : 0

  name       = local.cluster_autoscaler_release_name
  namespace  = "kube-system"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"

  dependency_update = true
  values = [
    templatefile(
      "${path.module}/templates/cluster-autoscaler-chart-values.yaml.tpl",
      {
        region       = var.region,
        svc_account  = local.cluster_autoscaler_service_account
        cluster_name = local.cluster_name,
        role_arn     = module.cluster_autoscaler_irsa_role[0].arn
      }
    )
  ]

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
  namespace  = "kube-system"
  atomic     = true
  timeout    = 900

  dependency_update = true
  values = [
    yamlencode({
      "clusterName" : local.cluster_name,
      "serviceAccount" : {
        "create" : false,
        "name" : kubernetes_service_account.lb_controller_sa[0].metadata[0].name
      },
      "region" : var.region,
      "vpcId" : var.vpc_id,
      "hostNetwork" : true
    })
  ]

  depends_on = [
    module.lb_irsa_role,
    kubernetes_service_account.lb_controller_sa
  ]
}

resource "helm_release" "external_dns" {
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
    value = module.cluster_exteranl_dns_irsa_role.arn
  }
  depends_on = [
    module.cluster_exteranl_dns_irsa_role
  ]
}
