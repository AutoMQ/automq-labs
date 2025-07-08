###############################################################################
# Cluster Autoscaler
# https://artifacthub.io/packages/helm/cluster-autoscaler/cluster-autoscaler
###############################################################################
resource "helm_release" "autoscaler" {
  count = local.enable_autoscaler ? 1 : 0


  name       = local.cluster_autoscaler_release_name
  namespace  = "kube-system"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"

  dependency_update = true
  values = [
    templatefile(
      "${path.module}/templates/cluster-autoscaler-chart-values.yaml.tpl",
      { region       = var.region,
        svc_account  = local.cluster_autoscaler_service_account
        cluster_name = local.cluster_name,
        role_arn     = module.cluster_autoscaler_irsa_role.iam_role_arn
      }
    )
  ]

  timeout = 600

  depends_on = [
    aws_eks_node_group.system-nodes, null_resource.kube_config
  ]
}

###############################################################################
# ALB Ingress Controller
# https://artifacthub.io/packages/helm/aws/aws-load-balancer-controller
# https://github.com/aws/eks-charts/tree/master/stable/aws-load-balancer-controller
# https://github.com/kubernetes-sigs/aws-load-balancer-controller
###############################################################################
resource "helm_release" "alb_controller" {
  name       = local.alb_controller_release_name
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  atomic     = true
  timeout    = 900

  dependency_update = true
  values = [
    yamlencode({
      "clusterName" : module.eks.cluster_name,
      "serviceAccount" : {
        "create" : false,
        "name" : kubernetes_service_account.lb_controller_sa.metadata[0].name
      },
      "region" : var.region,
      "vpcId" : local.vpc_id,
      "hostNetwork" : true
  })]

  depends_on = [
    aws_eks_node_group.system-nodes, null_resource.kube_config
  ]
}

