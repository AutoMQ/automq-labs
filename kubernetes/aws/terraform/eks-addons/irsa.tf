##############################################################################
# Load Balancer Controller Role
##############################################################################
module "lb_irsa_role" {
  count = var.enable_alb_ingress_controller ? 1 : 0

  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name                              = local.alb_controller_role_name
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = local.oidc_provider_arn
      namespace_service_accounts = ["kube-system:${local.lb_service_account}"]
    }
  }
}

##############################################################################
# EBS Storage CSI Role
##############################################################################
module "ebs-csi-irsa-role" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name             = local.ebs_csi_role_name
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = local.oidc_provider_arn
      namespace_service_accounts = ["kube-system:${local.ebs_csi_service_account}"]
    }
  }
}

##############################################################################
# Cluster Autoscaler Role
##############################################################################
module "cluster_autoscaler_irsa_role" {
  count = var.enable_autoscaler ? 1 : 0

  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name                        = local.cluster_autoscaler_role_name
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [var.cluster_name]

  oidc_providers = {
    main = {
      provider_arn               = local.oidc_provider_arn
      namespace_service_accounts = ["kube-system:${local.cluster_autoscaler_service_account}"]
    }
  }
}
