locals {
  automq_environment_id = nonsensitive(jsondecode(base64decode(var.automq_config)).environmentId)

  required_services = toset([
    "cloudresourcemanager.googleapis.com",
    "dns.googleapis.com",
    "iam.googleapis.com",
    "storage.googleapis.com",
  ])
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

module "console" {
  source = "./console"

  project_id           = var.project_id
  region               = var.region
  zone                 = var.zone
  name_prefix          = var.name_prefix
  network_id           = var.network_id
  management_subnet_id = var.management_subnet_id

  config                = var.automq_config
  console_image         = var.automq_console_image
  home_endpoint         = var.automq_home_endpoint
  machine_type          = var.console_machine_type
  ingress_source_ranges = var.console_ingress_source_ranges
  registry              = var.automq_console_registry

  depends_on = [google_project_service.required]
}
