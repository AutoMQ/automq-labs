##############################################################################
# Load Balancer Controller Role
##############################################################################
module "lb_irsa_role" {
  count = var.enable_alb_ingress_controller && !contains(keys(var.role_arns), "lb-controller") ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.11.0"

  name                                   = local.alb_controller_role_name
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
  count = var.enable_ebs_csi_driver && !contains(keys(var.role_arns), "ebs-csi") ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.11.0"

  name                  = local.ebs_csi_role_name
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
  count = var.enable_autoscaler && !contains(keys(var.role_arns), "autoscaler") ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.11.0"

  name                             = local.cluster_autoscaler_role_name
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [var.cluster_name]

  oidc_providers = {
    main = {
      provider_arn               = local.oidc_provider_arn
      namespace_service_accounts = ["kube-system:${local.cluster_autoscaler_service_account}"]
    }
  }
}

##############################################################################
# External DNS Role
##############################################################################
module "cluster_exteranl_dns_irsa_role" {
  count = var.enable_external_dns ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.11.0"

  name                          = local.external_dns_role_name
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = ["arn:aws:route53:::hostedzone/*"]


  oidc_providers = {
    main = {
      provider_arn = local.oidc_provider_arn
      // hardcoded for external-dns service account
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }
}
