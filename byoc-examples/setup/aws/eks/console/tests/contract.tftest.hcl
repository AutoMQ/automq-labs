mock_provider "aws" {
  mock_data "aws_eks_cluster" {
    defaults = {
      name                  = "automq-test-eks"
      endpoint              = "https://eks.example.test"
      certificate_authority = [{ data = "dGVzdA==" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE" }] }]
      vpc_config            = [{ cluster_security_group_id = "sg-example", subnet_ids = ["subnet-a", "subnet-b", "subnet-c"], vpc_id = "vpc-example" }]
    }
  }
}
mock_provider "kubernetes" {}
mock_provider "helm" {}
override_data {
  target = data.terraform_remote_state.infrastructure
  values = { outputs = {
    region                    = "us-east-1", account_id = "123456789012", environment_id = "env-example", ops_bucket_name = "automq-test-ops", vpc_id = "vpc-example"
    cluster_name              = "automq-test-eks", cluster_endpoint = "https://eks.example.test", cluster_certificate_authority_data = "dGVzdA==", kubernetes_version = "1.36"
    console_kubernetes_access = { principal_arn = "arn:aws:iam::123456789012:role/console", policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy", scope_type = "cluster" }
    console_namespace         = "automq-console", console_service_account_name = "automq-console", console_role_arn = "arn:aws:iam::123456789012:role/console"
    ebs_csi_role_arn          = "arn:aws:iam::123456789012:role/csi"
    lb_controller_role_arn    = "arn:aws:iam::123456789012:role/lb", autoscaler_role_arn = "arn:aws:iam::123456789012:role/as"
    private_subnet_ids_by_az  = { us-east-1a = "subnet-a", us-east-1b = "subnet-b", us-east-1c = "subnet-c" }
    automq_node_selector      = { "automq.io/pool" = "automq" }
    automq_tolerations        = [{ key = "dedicated", operator = "Equal", value = "automq", effect = "NoSchedule" }]
  } }
}
variables {
  automq_config = base64encode(jsonencode({ environmentId = "env-example", region = "us-east-1", opsBucket = { bucketName = "automq-test-ops" }, clientId = "fixture", clientSecret = "test-only" }))
  console_image = "registry.example.test/console:8.3.28-aws"
}
run "console_identity_storage_chart_contract" {
  command = apply
  assert {
    condition     = kubernetes_service_account_v1.console.automount_service_account_token && kubernetes_service_account_v1.console.metadata[0].annotations["eks.amazonaws.com/role-arn"] == local.infra.console_role_arn && local.infra.console_kubernetes_access.principal_arn == local.infra.console_role_arn && local.infra.console_kubernetes_access.scope_type == "cluster"
    error_message = "Console must use its exact KSA for IRSA and the Console Role Access Entry for Kubernetes."
  }
  assert {
    condition     = kubernetes_storage_class_v1.console.storage_provisioner == "ebs.csi.aws.com" && kubernetes_storage_class_v1.console.parameters.type == "gp3" && kubernetes_storage_class_v1.console.reclaim_policy == "Retain" && kubernetes_storage_class_v1.console.volume_binding_mode == "WaitForFirstConsumer"
    error_message = "Console requires encrypted gp3 CSI storage with explicit retention."
  }
  assert {
    condition     = nonsensitive(kubernetes_secret_v1.config.data.config) == nonsensitive(var.automq_config) && local.chart_values.automqByocConsole.config.existingSecret == kubernetes_secret_v1.config.metadata[0].name && local.chart_values.serviceAccount.name == local.infra.console_service_account_name && local.chart_values.service.type == "ClusterIP" && !local.chart_values.ingress.enabled && local.chart_values.nodeAffinities[0].values == ["system"] && helm_release.console.version == "8.3.28"
    error_message = "Chart must reference the external CONFIG secret/KSA and keep the Console on system nodes with private access."
  }
  assert {
    condition     = !contains(local.token_args, "--role-arn") && module.eks_addons.cluster_autoscaler_role_arn == local.infra.autoscaler_role_arn && module.eks_addons.alb_controller_role_arn == local.infra.lb_controller_role_arn
    error_message = "Tokens must use current deployer credentials and the shared components must reuse foundation Pod roles."

  }
}
run "released_console_image_is_accepted" {
  command = plan
  variables { console_image = "automq.azurecr.io/automq/automq-byoc-console:8.3.28-aws" }
  assert {
    condition     = local.chart_values.image.tag == "8.3.28-aws"
    error_message = "Released AWS Console tags must be supported with Access Entry authentication."
  }
}
run "latest_console_image_rejected" {
  command = plan
  variables { console_image = "automq.azurecr.io/automq/automq-byoc-console:latest" }
  expect_failures = [var.console_image]
}
run "snapshot_console_image_rejected" {
  command = plan
  variables { console_image = "registry.example.test/console:8.4.0-SNAPSHOT" }
  expect_failures = [var.console_image]
}
run "missing_console_access_entry_rejected" {
  command = plan
  override_data {
    target = data.terraform_remote_state.infrastructure
    values = { outputs = {
      region                   = "us-east-1", account_id = "123456789012", environment_id = "env-example", ops_bucket_name = "automq-test-ops", vpc_id = "vpc-example"
      cluster_name             = "automq-test-eks", cluster_endpoint = "https://eks.example.test", cluster_certificate_authority_data = "dGVzdA==", kubernetes_version = "1.36"
      console_namespace        = "automq-console", console_service_account_name = "automq-console", console_role_arn = "arn:aws:iam::123456789012:role/console"
      ebs_csi_role_arn         = "arn:aws:iam::123456789012:role/csi"
      lb_controller_role_arn   = "arn:aws:iam::123456789012:role/lb", autoscaler_role_arn = "arn:aws:iam::123456789012:role/as"
      private_subnet_ids_by_az = { us-east-1a = "subnet-a", us-east-1b = "subnet-b", us-east-1c = "subnet-c" }
      automq_node_selector     = { "automq.io/pool" = "automq" }, automq_tolerations = []
    } }
  }
  expect_failures = [terraform_data.contract]
}
run "mismatched_config_rejected" {
  command = plan
  variables { automq_config = base64encode(jsonencode({ environmentId = "env-other", region = "us-east-1", clientId = "fixture", clientSecret = "test-only", opsBucket = { bucketName = "automq-test-ops" } })) }
  expect_failures = [terraform_data.contract]
}
run "console_role_cannot_be_deployer" {
  command = plan
  variables { deployer_assume_role_arn = "arn:aws:iam::123456789012:role/console" }
  expect_failures = [terraform_data.contract]
}

run "wrong_console_access_principal_rejected" {
  command = plan
  override_data {
    target = data.terraform_remote_state.infrastructure
    values = { outputs = {
      region                    = "us-east-1", account_id = "123456789012", environment_id = "env-example", ops_bucket_name = "automq-test-ops", vpc_id = "vpc-example"
      cluster_name              = "automq-test-eks", cluster_endpoint = "https://eks.example.test", cluster_certificate_authority_data = "dGVzdA==", kubernetes_version = "1.36"
      console_kubernetes_access = { principal_arn = "arn:aws:iam::123456789012:role/node", policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy", scope_type = "cluster" }
      console_namespace         = "automq-console", console_service_account_name = "automq-console", console_role_arn = "arn:aws:iam::123456789012:role/console"
      ebs_csi_role_arn          = "arn:aws:iam::123456789012:role/csi"
      lb_controller_role_arn    = "arn:aws:iam::123456789012:role/lb", autoscaler_role_arn = "arn:aws:iam::123456789012:role/as"
      private_subnet_ids_by_az  = { us-east-1a = "subnet-a", us-east-1b = "subnet-b", us-east-1c = "subnet-c" }
      automq_node_selector      = { "automq.io/pool" = "automq" }
      automq_tolerations        = [{ key = "dedicated", operator = "Equal", value = "automq", effect = "NoSchedule" }]
    } }
  }
  expect_failures = [terraform_data.contract]
}

run "namespace_scoped_console_access_rejected" {
  command = plan
  override_data {
    target = data.terraform_remote_state.infrastructure
    values = { outputs = {
      region                    = "us-east-1", account_id = "123456789012", environment_id = "env-example", ops_bucket_name = "automq-test-ops", vpc_id = "vpc-example"
      cluster_name              = "automq-test-eks", cluster_endpoint = "https://eks.example.test", cluster_certificate_authority_data = "dGVzdA==", kubernetes_version = "1.36"
      console_kubernetes_access = { principal_arn = "arn:aws:iam::123456789012:role/console", policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy", scope_type = "namespace" }
      console_namespace         = "automq-console", console_service_account_name = "automq-console", console_role_arn = "arn:aws:iam::123456789012:role/console"
      ebs_csi_role_arn          = "arn:aws:iam::123456789012:role/csi"
      lb_controller_role_arn    = "arn:aws:iam::123456789012:role/lb", autoscaler_role_arn = "arn:aws:iam::123456789012:role/as"
      private_subnet_ids_by_az  = { us-east-1a = "subnet-a", us-east-1b = "subnet-b", us-east-1c = "subnet-c" }
      automq_node_selector      = { "automq.io/pool" = "automq" }
      automq_tolerations        = [{ key = "dedicated", operator = "Equal", value = "automq", effect = "NoSchedule" }]
    } }
  }
  expect_failures = [terraform_data.contract]
}
