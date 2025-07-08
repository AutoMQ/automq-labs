locals {
  lb_service_account                 = "aws-load-balancer-controller"
  ebs_csi_service_account            = "ebs-csi-controller-sa"
  cluster_autoscaler_service_account = "cluster-autoscaler"
}

##############################################################################
# Load Balancer Controller Role
#
# https://registry.terraform.io/modules/terraform-aws-modules/iam/aws/latest/submodules/iam-role-for-service-accounts-eks#input_attach_cluster_autoscaler_policy
##############################################################################
module "lb_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name                              = local.alb_controller_role_name
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:${local.lb_service_account}"]
    }
  }
}

##############################################################################
# EBS Storage CSI Role
# 
# This role is used by the EBS CSI driver to manage EBS volumes on your behalf.
# ServiceAccount: kube-system:ebs-csi-controller-sa
# 
# https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html
##############################################################################
module "ebs-csi-irsa-role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name             = local.ebs_csi_role_name
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:${local.ebs_csi_service_account}"]
    }
  }
}
# module "ebs-csi-irsa-role" {
#   source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
#   version = "5.39.0"

#   create_role                   = true
#   role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
#   provider_url                  = module.eks.oidc_provider
#   role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
#   oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
# }

# # https://aws.amazon.com/blogs/containers/amazon-ebs-csi-driver-is-now-generally-available-in-amazon-eks-add-ons/
# data "aws_iam_policy" "ebs_csi_policy" {
#   arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
# }


##############################################################################
# Cluster Autoscaler Role
# 
# https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md
##############################################################################
module "cluster_autoscaler_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name                        = local.cluster_autoscaler_role_name
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [module.eks.cluster_name]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:${local.cluster_autoscaler_service_account}"]
    }
  }
}
# module "irsa-autoscaler-role" {
#   source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
#   version = "5.39.0"

#   create_role                   = true
#   role_name                     = "cluster-autoscaler-${module.eks.cluster_name}"
#   provider_url                  = module.eks.oidc_provider
#   role_policy_arns              = [aws_iam_policy.cluster_autoscaler.arn]
#   oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:${local.k8s_service_account_name}"]
# }


# resource "aws_iam_policy" "cluster_autoscaler" {
#   name_prefix = "${local.vpc_name}-cluster-autoscaler"
#   description = "EKS cluster-autoscaler policy for cluster ${module.eks.cluster_name}"
#   policy      = data.aws_iam_policy_document.cluster_autoscaler.json
# }

# data "aws_caller_identity" "current" {}

# # https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md
# data "aws_iam_policy_document" "cluster_autoscaler" {
#   statement {
#     sid    = "clusterAutoscalerAll"
#     effect = "Allow"

#     actions = [
#       "autoscaling:DescribeAutoScalingGroups",
#       "autoscaling:DescribeAutoScalingInstances",
#       "autoscaling:DescribeLaunchConfigurations",
#       "autoscaling:DescribeTags",
#       "ec2:DescribeInstanceTypes",
#       "ec2:DescribeLaunchTemplateVersions",
#     ]

#     resources = ["*"]
#   }

#   statement {
#     sid    = "clusterAutoscalerOwn"
#     effect = "Allow"

#     actions = [
#       "autoscaling:SetDesiredCapacity",
#       "autoscaling:TerminateInstanceInAutoScalingGroup",
#     ]

#     resources = ["arn:aws:autoscaling:*:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/*"]
#   }
# }
