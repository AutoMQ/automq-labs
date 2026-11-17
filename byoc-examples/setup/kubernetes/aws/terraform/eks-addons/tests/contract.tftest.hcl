mock_provider "aws" {
  mock_data "aws_eks_cluster" {
    defaults = {
      endpoint              = "https://eks.example.test"
      certificate_authority = [{ data = "dGVzdA==" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE" }] }]
      vpc_config            = [{ cluster_security_group_id = "sg-example", subnet_ids = ["subnet-a", "subnet-b"], vpc_id = "vpc-example" }]
    }
  }
  mock_data "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE" }
  }
}
mock_provider "kubernetes" {}
mock_provider "helm" {
  mock_resource "helm_release" { defaults = { status = "deployed" } }
}

variables {
  region          = "us-east-1"
  cluster_name    = "fixture-eks"
  vpc_id          = "vpc-example"
  resource_suffix = "fixture"
}

run "existing_addons_keep_owned_roles_and_releases" {
  command = apply
  override_module {
    target  = module.cluster_autoscaler_irsa_role[0]
    outputs = { arn = "arn:aws:iam::123456789012:role/legacy-ca" }
  }
  override_module {
    target  = module.lb_irsa_role[0]
    outputs = { arn = "arn:aws:iam::123456789012:role/legacy-lb" }
  }
  override_module {
    target  = module.ebs-csi-irsa-role[0]
    outputs = { arn = "arn:aws:iam::123456789012:role/legacy-csi" }
  }
  override_module {
    target  = module.cluster_exteranl_dns_irsa_role[0]
    outputs = { arn = "arn:aws:iam::123456789012:role/legacy-dns" }
  }
  assert {
    condition = (
      length(module.cluster_autoscaler_irsa_role) == 1 && length(module.lb_irsa_role) == 1 && length(module.ebs-csi-irsa-role) == 1 &&
      length(module.cluster_exteranl_dns_irsa_role) == 1 && length(helm_release.external_dns) == 1 &&
      length(aws_vpc_security_group_ingress_rule.automq_ingress_rule) == 1 && length(kubernetes_service_account.lb_controller_sa) == 1 &&
      output.cluster_autoscaler_role_arn == "arn:aws:iam::123456789012:role/legacy-ca"
    )
    error_message = "Existing callers must retain module-owned IRSA, ExternalDNS, ingress and the separately managed LB ServiceAccount."
  }
  assert {
    condition = (
      yamldecode(helm_release.alb_controller[0].values[0]).hostNetwork == true &&
      yamldecode(helm_release.alb_controller[0].values[0]).serviceAccount.create == false &&
      helm_release.autoscaler[0].version == "9.59.0" && one(helm_release.autoscaler[0].set).value == "v1.36.1" &&
      yamldecode(helm_release.autoscaler[0].values[0]).rbac.serviceAccount.annotations["eks.amazonaws.com/role-arn"] == "arn:aws:iam::123456789012:role/legacy-ca"
    )
    error_message = "Existing Helm defaults must keep their networking, ServiceAccount ownership and CA version."
  }
}

run "external_roles_reuse_existing_foundation" {
  command = apply
  variables {
    role_arns = {
      autoscaler    = "arn:aws:iam::123456789012:role/fixture-autoscaler"
      lb-controller = "arn:aws:iam::123456789012:role/fixture-lb-controller"
      ebs-csi       = "arn:aws:iam::123456789012:role/fixture-ebs-csi"
    }
    enable_ebs_csi_driver       = false
    enable_external_dns         = false
    enable_automq_ingress_rule  = false
    enable_vpc_cni              = false
    enable_coredns              = false
    enable_kube_proxy           = false
    enable_pod_identity_agent   = false
    manage_lb_service_account   = false
    autoscaler_image_tag        = "v1.36.0"
    lb_controller_chart_version = "1.13.4"
    lb_controller_host_network  = false
    autoscaler_values           = [jsonencode({ nodeSelector = { "automq.io/pool" = "system" }, extraArgs = { "balance-similar-node-groups" = "true", "skip-nodes-with-local-storage" = "false" } })]
    lb_controller_values        = [jsonencode({ nodeSelector = { "automq.io/pool" = "system" } })]
  }
  assert {
    condition = (
      length(module.cluster_autoscaler_irsa_role) == 0 && length(module.lb_irsa_role) == 0 && length(module.ebs-csi-irsa-role) == 0 &&
      length(module.cluster_exteranl_dns_irsa_role) == 0 && length(helm_release.external_dns) == 0 &&
      length(aws_vpc_security_group_ingress_rule.automq_ingress_rule) == 0 && length(kubernetes_service_account.lb_controller_sa) == 0 &&
      length(aws_eks_addon.vpc_cni) == 0 && length(aws_eks_addon.coredns) == 0 && length(aws_eks_addon.kube_proxy) == 0 &&
      length(aws_eks_addon.pod_identity_agent) == 0 && length(aws_eks_addon.aws_ebs_csi_driver) == 0
    )
    error_message = "A separate Helm stage must not duplicate foundation roles, managed addons, DNS, SG rules or a Chart-owned ServiceAccount."
  }
  assert {
    condition = (
      helm_release.autoscaler[0].version == "9.59.0" && one(helm_release.autoscaler[0].set).value == "v1.36.0" &&
      helm_release.alb_controller[0].version == "1.13.4" &&
      yamldecode(helm_release.autoscaler[0].values[0]).rbac.serviceAccount.name == "cluster-autoscaler" &&
      yamldecode(helm_release.autoscaler[0].values[0]).rbac.serviceAccount.annotations["eks.amazonaws.com/role-arn"] == var.role_arns["autoscaler"] &&
      yamldecode(helm_release.alb_controller[0].values[0]).serviceAccount.name == "aws-load-balancer-controller" &&
      yamldecode(helm_release.alb_controller[0].values[0]).serviceAccount.create == true &&
      yamldecode(helm_release.alb_controller[0].values[0]).serviceAccount.annotations["eks.amazonaws.com/role-arn"] == var.role_arns["lb-controller"] &&
      yamldecode(helm_release.alb_controller[0].values[0]).hostNetwork == false
    )
    error_message = "The customer example must retain matching Chart/images and exact external component ServiceAccounts without host networking."
  }
  assert {
    condition = (
      yamldecode(helm_release.autoscaler[0].values[1]).nodeSelector["automq.io/pool"] == "system" &&
      yamldecode(helm_release.alb_controller[0].values[1]).nodeSelector["automq.io/pool"] == "system"
    )
    error_message = "Infrastructure controllers must be scheduled on the system pool."
  }
}
