data "terraform_remote_state" "console" {
  backend = "local"

  config = {
    path = abspath(var.console_state_path)
  }
}

locals {
  console_endpoint   = try(data.terraform_remote_state.console.outputs.console_endpoint, "")
  console_access_key = try(data.terraform_remote_state.console.outputs.console_initial_access_key, "")
  console_secret_key = try(data.terraform_remote_state.console.outputs.console_initial_secret_key, "")
  environment_id     = try(data.terraform_remote_state.console.outputs.environment_id, "")
  broker_networks = try(tolist([
    for network in data.terraform_remote_state.console.outputs.broker_networks : {
      zone    = network.zone
      subnets = tolist(network.subnets)
    }
  ]), [])
  data_bucket_name   = try(data.terraform_remote_state.console.outputs.data_bucket_name, "")
  dns_zone_id        = try(data.terraform_remote_state.console.outputs.dns_zone_id, "")
  instance_role_name = try(data.terraform_remote_state.console.outputs.cluster_role_name, "")

  console_endpoint_valid   = can(regex("^https?://[^[:space:]]+$", local.console_endpoint))
  console_access_key_valid = length(trimspace(local.console_access_key)) > 0
  console_secret_key_valid = length(trimspace(local.console_secret_key)) > 0
  broker_networks_valid = try(
    contains([1, 3], length(local.broker_networks)) &&
    length(distinct([for network in local.broker_networks : network.zone])) == length(local.broker_networks) &&
    length(distinct(flatten([for network in local.broker_networks : network.subnets]))) == length(local.broker_networks) &&
    alltrue([
      for network in local.broker_networks :
      trimspace(network.zone) != "" &&
      length(network.subnets) == 1 &&
      can(regex("^subnet-([0-9a-f]{8}|[0-9a-f]{17})$", network.subnets[0]))
    ]),
    false,
  )
  console_state_valid = (
    local.console_endpoint_valid &&
    local.console_access_key_valid &&
    local.console_secret_key_valid &&
    can(regex("^env-[A-Za-z0-9]+$", local.environment_id)) &&
    local.broker_networks_valid &&
    length(local.data_bucket_name) >= 3 &&
    length(local.data_bucket_name) <= 63 &&
    can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", local.data_bucket_name)) &&
    !strcontains(local.data_bucket_name, "..") &&
    can(regex("^Z[A-Z0-9]+$", local.dns_zone_id)) &&
    can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", local.instance_role_name))
  )
}
