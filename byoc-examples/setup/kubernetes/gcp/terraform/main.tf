locals {
  required_services = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
  ])

  automq_ports = [
    "8081",
    "8083",
    "9090",
    "9092",
    "9093",
    "9102",
    "9103",
    "9112",
    "9113",
  ]
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

module "network" {
  source = "./network"

  project_id    = var.project_id
  region        = var.region
  name_prefix   = var.name_prefix
  network_cidrs = var.network_cidrs

  depends_on = [google_project_service.required]
}

module "gke" {
  source = "./gke"

  project_id                   = var.project_id
  region                       = var.region
  zones                        = var.zones
  name_prefix                  = var.name_prefix
  network_id                   = module.network.vpc_id
  workload_subnet_id           = module.network.workload_subnet_id
  pod_secondary_range_name     = module.network.pod_secondary_range_name
  service_secondary_range_name = module.network.service_secondary_range_name
  automq_node_pool             = var.automq_node_pool

  depends_on = [google_project_service.required]
}

resource "google_compute_firewall" "management_to_automq" {
  project = var.project_id
  name    = "${var.name_prefix}-management-to-automq"
  network = module.network.vpc_id

  direction     = "INGRESS"
  source_ranges = [module.network.management_subnet_cidr]
  target_tags   = [module.gke.automq_network_tag]

  allow {
    protocol = "tcp"
    ports    = local.automq_ports
  }
}
