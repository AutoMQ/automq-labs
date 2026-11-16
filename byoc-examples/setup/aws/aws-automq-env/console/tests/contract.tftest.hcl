mock_provider "kubernetes" {}
mock_provider "helm" {}
override_data {
  target = data.terraform_remote_state.infrastructure
  values = { outputs = {
    region                   = "us-east-1", account_id = "123456789012", environment_id = "env-example", ops_bucket_name = "automq-test-ops", vpc_id = "vpc-example"
    cluster_name             = "automq-test-eks", cluster_endpoint = "https://eks.example.test", cluster_certificate_authority_data = "dGVzdA==", kubernetes_version = "1.36"
    console_namespace        = "automq-console", console_service_account_name = "automq-console", console_role_arn = "arn:aws:iam::123456789012:role/console"
    lb_controller_role_arn   = "arn:aws:iam::123456789012:role/lb", autoscaler_role_arn = "arn:aws:iam::123456789012:role/as"
    private_subnet_ids_by_az = { us-east-1a = "subnet-a", us-east-1b = "subnet-b", us-east-1c = "subnet-c" }
    automq_node_selector     = { "automq.io/pool" = "automq" }
    automq_tolerations       = [{ key = "dedicated", operator = "Equal", value = "automq", effect = "NoSchedule" }]
  } }
}
variables {
  automq_config = base64encode(jsonencode({ environmentId = "env-example", region = "us-east-1", opsBucket = { bucketName = "automq-test-ops" }, clientId = "fixture", clientSecret = "test-only" }))
  console_image = "registry.example.test/console:sa-trust-s3wal"
}
run "console_identity_storage_chart_contract" {
  command = apply
  assert {
    condition     = kubernetes_service_account_v1.console.automount_service_account_token && kubernetes_service_account_v1.console.metadata[0].annotations["eks.amazonaws.com/role-arn"] == local.infra.console_role_arn && kubernetes_cluster_role_binding_v1.console.role_ref[0].name == "cluster-admin" && kubernetes_cluster_role_binding_v1.console.subject[0].namespace == local.infra.console_namespace
    error_message = "Console must use its exact KSA for IRSA and cluster-admin RBAC."
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
    condition     = !contains(local.token_args, "--role-arn") && helm_release.lb_controller.version == "1.13.4" && yamldecode(helm_release.autoscaler.values[0]).image.tag == "v1.36.0" && yamldecode(helm_release.lb_controller.values[0]).serviceAccount.name == "aws-load-balancer-controller" && yamldecode(helm_release.autoscaler.values[0]).rbac.serviceAccount.name == "cluster-autoscaler"
    error_message = "Tokens must use current deployer credentials and component KSAs must match foundation trust."
  }
}
run "old_console_image_rejected" {
  command = plan
  variables { console_image = "automq.azurecr.io/automq/automq-byoc-console:8.3.28-aws" }
  expect_failures = [var.console_image]
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
