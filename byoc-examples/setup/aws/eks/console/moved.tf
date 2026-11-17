# Keep the installed Helm releases while handing their configuration to the
# common EKS addons module.
moved {
  from = helm_release.autoscaler
  to   = module.eks_addons.helm_release.autoscaler[0]
}

moved {
  from = helm_release.lb_controller
  to   = module.eks_addons.helm_release.alb_controller[0]
}
