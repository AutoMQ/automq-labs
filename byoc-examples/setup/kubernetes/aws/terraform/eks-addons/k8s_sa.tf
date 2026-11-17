resource "kubernetes_service_account" "lb_controller_sa" {
  count = var.enable_alb_ingress_controller && var.manage_lb_service_account ? 1 : 0

  automount_service_account_token = true
  metadata {
    name      = local.lb_service_account
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = local.alb_controller_role_arn
    }
    labels = {
      "app.kubernetes.io/name"       = local.lb_service_account
      "app.kubernetes.io/component"  = "controller"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
  depends_on = [module.lb_irsa_role]
}
