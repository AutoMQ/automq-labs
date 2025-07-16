resource "kubernetes_service_account" "lb_controller_sa" {
  count = var.enable_alb_ingress_controller ? 1 : 0

  automount_service_account_token = true
  metadata {
    name      = local.lb_service_account
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.lb_irsa_role[0].iam_role_arn
    }
    labels = {
      "app.kubernetes.io/name"       = local.lb_service_account
      "app.kubernetes.io/component"  = "controller"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
  depends_on = [module.lb_irsa_role]
}
