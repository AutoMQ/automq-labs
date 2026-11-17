mock_provider "automq" {}
override_data {
  target = data.terraform_remote_state.instance
  values = { outputs = { environment_id = "env-example", instance_id = "kf-example" } }
}
variables { kafka_password = "test-only-password-012345" }
run "scoped_kafka_identity" {
  command = apply
  assert {
    condition     = automq_kafka_topic.smoke.partition == 1 && automq_kafka_acl.topic.resource_name == automq_kafka_topic.smoke.name && automq_kafka_acl.topic.principal == "User:eks-smoke" && automq_kafka_acl.group.resource_type == "GROUP" && automq_kafka_acl.group.pattern_type == "PREFIXED" && automq_kafka_acl.group.resource_name == "eks-smoke-"
    error_message = "Smoke identity must be scoped to its topic and consumer groups."
  }
}
run "short_password_rejected" {
  command = plan
  variables { kafka_password = "short" }
  expect_failures = [var.kafka_password]
}
