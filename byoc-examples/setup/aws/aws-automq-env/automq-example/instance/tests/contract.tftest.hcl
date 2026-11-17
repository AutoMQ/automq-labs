mock_provider "automq" {}
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
variables { automq_version = "5.5.6" }
run "managed_three_az_s3wal" {
  command = apply
  assert {
    condition     = automq_kafka_instance.demo.compute_specs.deploy_type == "K8S" && automq_kafka_instance.demo.compute_specs.pricing_mode == "UsageBased" && automq_kafka_instance.demo.compute_specs.reserved_node_count == 3 && automq_kafka_instance.demo.compute_specs.kubernetes_cluster_id == "automq-test-eks" && length(automq_kafka_instance.demo.compute_specs.networks) == 3 && length(automq_kafka_instance.demo.compute_specs.kubernetes_load_balancer_subnets) == 3 && automq_kafka_instance.demo.features.wal_mode == "S3WAL"
    error_message = "Managed K8S Instance must use three AZs/private NLB subnets and three UsageBased S3WAL nodes."
  }
  assert {
    condition     = alltrue([for key in ["data_buckets", "instance_role", "dns_zone", "kubernetes_namespace", "kubernetes_service_account"] : !contains(keys(local.instance_compute_specs), key)]) && toset(keys(yamldecode(automq_kafka_instance.demo.compute_specs.schedule_spec))) == toset(["affinity", "tolerations"]) && yamldecode(automq_kafka_instance.demo.compute_specs.schedule_spec).affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions == [{ key = "automq.io/pool", operator = "In", values = ["automq"] }] && yamldecode(automq_kafka_instance.demo.compute_specs.schedule_spec).tolerations[0].effect == "NoSchedule" && contains(automq_kafka_instance.demo.features.security.authentication_methods, "sasl") && contains(automq_kafka_instance.demo.features.security.transit_encryption_modes, "plaintext")
    error_message = "CMP must own Data Bucket/role/DNS/namespace/KSA; scheduling and SASL_PLAINTEXT must be explicit."
  }
}
run "console_version_rejected" {
  command = plan
  variables { automq_version = "8.3.28" }
  expect_failures = [var.automq_version]
}
run "two_subnets_rejected" {
  command = plan
  override_data {
    target = data.terraform_remote_state.infrastructure
    values = { outputs = {
      region                   = "us-east-1", account_id = "123456789012", environment_id = "env-example", ops_bucket_name = "automq-test-ops", vpc_id = "vpc-example"
      cluster_name             = "automq-test-eks", cluster_endpoint = "https://eks.example.test", cluster_certificate_authority_data = "dGVzdA==", kubernetes_version = "1.36"
      console_namespace        = "automq-console", console_service_account_name = "automq-console", console_role_arn = "arn:aws:iam::123456789012:role/console"
      lb_controller_role_arn   = "arn:aws:iam::123456789012:role/lb", autoscaler_role_arn = "arn:aws:iam::123456789012:role/as"
      private_subnet_ids_by_az = { us-east-1a = "subnet-a", us-east-1b = "subnet-b" }
      automq_node_selector     = { "automq.io/pool" = "automq" }
      automq_tolerations       = [{ key = "dedicated", operator = "Equal", value = "automq", effect = "NoSchedule" }]
    } }
  }
  expect_failures = [automq_kafka_instance.demo]
}

# Product K8sScheduleSpecParam accepts only affinity/tolerations; all selector
# labels must form AND expressions in one term, rather than separate OR terms.
run "multiple_selector_labels_use_required_affinity" {
  command = plan
  override_data {
    target = data.terraform_remote_state.infrastructure
    values = { outputs = {
      region                   = "us-east-1", account_id = "123456789012", environment_id = "env-example", ops_bucket_name = "automq-test-ops", vpc_id = "vpc-example"
      cluster_name             = "automq-test-eks", cluster_endpoint = "https://eks.example.test", cluster_certificate_authority_data = "dGVzdA==", kubernetes_version = "1.36"
      console_namespace        = "automq-console", console_service_account_name = "automq-console", console_role_arn = "arn:aws:iam::123456789012:role/console"
      lb_controller_role_arn   = "arn:aws:iam::123456789012:role/lb", autoscaler_role_arn = "arn:aws:iam::123456789012:role/as"
      private_subnet_ids_by_az = { us-east-1a = "subnet-a", us-east-1b = "subnet-b", us-east-1c = "subnet-c" }
      automq_node_selector     = { "automq.io/pool" = "automq", "example.com/workload" = "kafka" }
      automq_tolerations       = [{ key = "dedicated", operator = "Equal", value = "automq", effect = "NoSchedule" }]
    } }
  }
  assert {
    condition     = length(yamldecode(local.instance_compute_specs.schedule_spec).affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms) == 1 && length(yamldecode(local.instance_compute_specs.schedule_spec).affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions) == 2 && alltrue([for expression in yamldecode(local.instance_compute_specs.schedule_spec).affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions : expression.operator == "In" && expression.values == [local.infra.automq_node_selector[expression.key]]])
    error_message = "Every foundation selector label must become a required In expression in the same AND term."
  }
}

run "six_nodes_for_scale_out" {
  command = plan
  variables { instance_node_count = 6 }
  assert {
    condition     = automq_kafka_instance.demo.compute_specs.reserved_node_count == 6 && length(automq_kafka_instance.demo.compute_specs.networks) == 3
    error_message = "Scaling must change the requested Instance count while retaining its three AZ network configuration."
  }
}
run "four_nodes_is_an_allowed_integer" {
  command = plan
  variables { instance_node_count = 4 }
  assert {
    condition     = automq_kafka_instance.demo.compute_specs.reserved_node_count == 4
    error_message = "The example must not impose an unsupported multiple-of-three node count restriction."
  }
}
run "fewer_than_three_nodes_rejected" {
  command = plan
  variables { instance_node_count = 2 }
  expect_failures = [var.instance_node_count]
}
run "fractional_nodes_rejected" {
  command = plan
  variables { instance_node_count = 3.5 }
  expect_failures = [var.instance_node_count]
}
