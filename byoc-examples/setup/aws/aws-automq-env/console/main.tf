data "terraform_remote_state" "infrastructure" {
  backend = "local"
  config  = { path = var.infrastructure_state_path }
}
locals {
  infra       = data.terraform_remote_state.infrastructure.outputs
  token_args  = concat(["eks", "get-token", "--region", local.infra.region, "--cluster-name", local.infra.cluster_name], var.deployer_assume_role_arn == null ? [] : ["--role-arn", var.deployer_assume_role_arn])
  image_parts = try(regex("^(.+):([^/:]+)$", var.console_image), ["invalid", "invalid"])
  config      = try(jsondecode(base64decode(var.automq_config)), {})
  chart_values = {
    fullnameOverride  = "automq-console"
    cloudProvider     = "aws"
    automqByocConsole = { config = { existingSecret = "automq-console-config" } }
    aws               = { account = local.infra.account_id, network = { vpcId = local.infra.vpc_id, subnetIds = values(local.infra.private_subnet_ids_by_az) } }
    image             = { repository = local.image_parts[0], tag = local.image_parts[1], pullPolicy = "IfNotPresent" }
    serviceAccount    = { name = local.infra.console_service_account_name }
    nodeAffinities    = [{ key = "automq.io/pool", values = ["system"] }]
    persistence       = { storageClass = "automq-console-gp3", accessModes = ["ReadWriteOnce"], size = "20Gi" }
    service           = { type = "ClusterIP", ports = { web = 80 } }
    ingress           = { enabled = false }
    resources         = { requests = { cpu = "1000m", memory = "4Gi" }, limits = { cpu = "2000m", memory = "8Gi" } }
  }
}
provider "kubernetes" {
  host                   = local.infra.cluster_endpoint
  cluster_ca_certificate = base64decode(local.infra.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.token_args
  }
}
provider "helm" {
  kubernetes {
    host                   = local.infra.cluster_endpoint
    cluster_ca_certificate = base64decode(local.infra.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.token_args
    }
  }
}
resource "terraform_data" "contract" {
  lifecycle {
    precondition {
      condition     = try(local.config.environmentId == local.infra.environment_id && local.config.region == local.infra.region && local.config.opsBucket.bucketName == local.infra.ops_bucket_name, false)
      error_message = "CONFIG environment, region and Ops bucket must match infrastructure state."
    }
    precondition {
      condition = try(
        local.infra.console_kubernetes_access.principal_arn == local.infra.console_role_arn &&
        local.infra.console_kubernetes_access.policy_arn == "arn:${split(":", local.infra.console_role_arn)[1]}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" &&
        local.infra.console_kubernetes_access.scope_type == "cluster", false
      )
      error_message = "Foundation must grant the Console Role cluster-scoped AmazonEKSClusterAdminPolicy through its EKS Access Entry before installing Console."
    }
    precondition {
      condition     = local.infra.kubernetes_version == "1.36" && (var.deployer_assume_role_arn == null || var.deployer_assume_role_arn != local.infra.console_role_arn)
      error_message = "This component matrix requires EKS 1.36. The deployer must not assume the Console role."
    }
  }
}
resource "kubernetes_namespace_v1" "console" {
  metadata {
    name = local.infra.console_namespace
  }
  depends_on = [terraform_data.contract]
}
resource "kubernetes_service_account_v1" "console" {
  metadata {
    name        = local.infra.console_service_account_name
    namespace   = kubernetes_namespace_v1.console.metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" = local.infra.console_role_arn }
  }
  automount_service_account_token = true
}
resource "kubernetes_secret_v1" "config" {
  metadata {
    name      = "automq-console-config"
    namespace = kubernetes_namespace_v1.console.metadata[0].name
  }
  data = { config = var.automq_config }
  type = "Opaque"
}
resource "kubernetes_storage_class_v1" "console" {
  metadata {
    name = "automq-console-gp3"
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters             = { type = "gp3", encrypted = "true", "csi.storage.k8s.io/fstype" = "ext4" }
}
resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.13.4"
  wait       = true
  timeout    = 600
  values = [yamlencode({
    clusterName    = local.infra.cluster_name, region = local.infra.region, vpcId = local.infra.vpc_id
    serviceAccount = { create = true, name = "aws-load-balancer-controller", annotations = { "eks.amazonaws.com/role-arn" = local.infra.lb_controller_role_arn } }
    nodeSelector   = { "automq.io/pool" = "system" }
  })]
  depends_on = [terraform_data.contract]
}
resource "helm_release" "autoscaler" {
  name       = "cluster-autoscaler"
  namespace  = "kube-system"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.59.0"
  wait       = true
  timeout    = 600
  values = [yamlencode({
    cloudProvider = "aws", awsRegion = local.infra.region
    autoDiscovery = { clusterName = local.infra.cluster_name }
    image         = { repository = "registry.k8s.io/autoscaling/cluster-autoscaler", tag = "v1.36.0" }
    rbac          = { serviceAccount = { create = true, name = "cluster-autoscaler", annotations = { "eks.amazonaws.com/role-arn" = local.infra.autoscaler_role_arn } } }
    nodeSelector  = { "automq.io/pool" = "system" }
    extraArgs     = { "balance-similar-node-groups" = "true", "skip-nodes-with-local-storage" = "false" }
  })]
  depends_on = [terraform_data.contract]
}
resource "helm_release" "console" {
  name       = "automq-console"
  namespace  = kubernetes_namespace_v1.console.metadata[0].name
  repository = var.console_chart_path == null ? "oci://automq.azurecr.io/helm" : null
  chart      = var.console_chart_path == null ? "automq-byoc-console-chart" : var.console_chart_path
  version    = "8.3.28"
  wait       = true
  timeout    = 900
  values     = [yamlencode(local.chart_values)]
  depends_on = [kubernetes_service_account_v1.console, kubernetes_secret_v1.config, kubernetes_storage_class_v1.console, helm_release.lb_controller, helm_release.autoscaler]
}
