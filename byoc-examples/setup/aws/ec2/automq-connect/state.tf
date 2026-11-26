data "terraform_remote_state" "console" {
  backend = "local"

  config = {
    path = abspath(var.console_state_path)
  }
}

data "terraform_remote_state" "kafka" {
  backend = "local"

  config = {
    path = abspath(var.kafka_state_path)
  }
}

locals {
  console_endpoint = var.console_endpoint_override != null ? trimsuffix(var.console_endpoint_override, "/") : try(
    data.terraform_remote_state.console.outputs.console_endpoint, "",
  )
  console_access_key        = sensitive(try(data.terraform_remote_state.console.outputs.console_initial_access_key, ""))
  console_secret_key        = sensitive(try(data.terraform_remote_state.console.outputs.console_initial_secret_key, ""))
  environment_id            = try(data.terraform_remote_state.console.outputs.environment_id, "")
  kafka_instance_id         = try(data.terraform_remote_state.kafka.outputs.instance_id, "")
  console_region            = try(data.terraform_remote_state.console.outputs.region, "")
  console_role_arn          = try(data.terraform_remote_state.console.outputs.console_role_arn, "")
  console_security_group_id = try(data.terraform_remote_state.console.outputs.console_security_group_id, "")
  ops_bucket_name           = try(data.terraform_remote_state.console.outputs.ops_bucket_name, "")
  ops_bucket_arn            = "arn:${data.aws_partition.current.partition}:s3:::${local.ops_bucket_name}"

  # A missing Console Region is rejected by preflight; keep provider setup valid.
  aws_region = coalesce(var.aws_region, local.console_region, "us-east-1")

  console_endpoint_valid       = can(regex("^https?://[^[:space:]]+$", local.console_endpoint))
  console_access_key_valid     = length(trimspace(local.console_access_key)) > 0
  console_secret_key_valid     = length(trimspace(local.console_secret_key)) > 0
  console_security_group_valid = can(regex("^sg-([0-9a-f]{8}|[0-9a-f]{17})$", local.console_security_group_id))
  console_state_valid = (
    local.console_endpoint_valid &&
    local.console_access_key_valid &&
    local.console_secret_key_valid &&
    local.console_security_group_valid &&
    length(trimspace(local.console_region)) > 0 &&
    can(regex("^arn:(aws|aws-cn|aws-us-gov):iam::[0-9]{12}:role/.+$", local.console_role_arn)) &&
    can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", local.ops_bucket_name)) &&
    can(regex("^env-[A-Za-z0-9]+$", local.environment_id))
  )
  kafka_state_valid = can(regex("^kf-[A-Za-z0-9_-]+$", local.kafka_instance_id))
}
