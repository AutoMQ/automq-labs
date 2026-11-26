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
  gke_id_parts     = try(regex("^projects/([^/]+)/locations/([^/]+)/clusters/([^/]+)$", var.kubernetes_cluster_id), ["invalid-project", "invalid-location", "invalid-cluster"])
  gke_project_id   = local.gke_id_parts[0]
  gke_location     = local.gke_id_parts[1]
  gke_cluster_name = local.gke_id_parts[2]

  environment_id                = try(data.terraform_remote_state.console.outputs.automq_environment_id, "")
  console_project               = try(data.terraform_remote_state.console.outputs.project_id, "")
  console_region                = try(data.terraform_remote_state.console.outputs.region, "")
  console_network               = try(data.terraform_remote_state.console.outputs.network_id, "")
  console_service_account_email = try(data.terraform_remote_state.console.outputs.console_service_account_email, "")
  console_endpoint = var.console_endpoint_override != null ? trimsuffix(var.console_endpoint_override, "/") : try(
    data.terraform_remote_state.console.outputs.console_endpoint, "",
  )
  console_access_key = sensitive(try(data.terraform_remote_state.console.outputs.console_initial_access_key, ""))
  console_secret_key = sensitive(try(data.terraform_remote_state.console.outputs.console_initial_secret_key, ""))
  kafka_instance_id  = try(data.terraform_remote_state.kafka.outputs.instance_id, "")
  ops_bucket_name    = try(data.terraform_remote_state.console.outputs.ops_bucket_name, "")

  console_endpoint_valid   = can(regex("^https?://[^[:space:]]+$", local.console_endpoint))
  console_access_key_valid = length(trimspace(local.console_access_key)) > 0
  console_secret_key_valid = length(trimspace(local.console_secret_key)) > 0
  console_state_valid = (
    local.console_endpoint_valid && local.console_access_key_valid && local.console_secret_key_valid &&
    can(regex("^env-[A-Za-z0-9]+$", local.environment_id)) &&
    trimspace(local.console_project) != "" && trimspace(local.console_region) != "" &&
    can(regex("^projects/[^/]+/global/networks/[^/]+$", local.console_network)) &&
    endswith(local.console_service_account_email, "@${local.console_project}.iam.gserviceaccount.com")
  )
  kafka_state_valid = can(regex("^kf-[A-Za-z0-9_-]+$", local.kafka_instance_id))
}
