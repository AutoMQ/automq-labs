# https://artifacthub.io/packages/helm/aws/aws-load-balancer-controller?modal=template&template=rbac.yaml
resource "kubernetes_service_account" "lb_controller_sa" {
  automount_service_account_token = true
  metadata {
    name      = local.lb_service_account
    namespace = "kube-system"
    annotations = {
      # This annotation is only used when running on EKS which can
      # use IAM roles for service accounts.
      "eks.amazonaws.com/role-arn" = module.lb_irsa_role.iam_role_arn
    }
    labels = {
      "app.kubernetes.io/name"       = local.lb_service_account
      "app.kubernetes.io/component"  = "controller"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
  depends_on = [ module.eks ]
}


