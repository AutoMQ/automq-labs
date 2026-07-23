locals {
  pod_secondary_range_name     = "${var.name_prefix}-pods"
  service_secondary_range_name = "${var.name_prefix}-services"
}

resource "google_compute_network" "main" {
  project                 = var.project_id
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "management" {
  project                  = var.project_id
  name                     = "${var.name_prefix}-management"
  region                   = var.region
  network                  = google_compute_network.main.id
  ip_cidr_range            = var.network_cidrs.management
  private_ip_google_access = true
  stack_type               = "IPV4_ONLY"
}

resource "google_compute_subnetwork" "workload" {
  project                  = var.project_id
  name                     = "${var.name_prefix}-workload"
  region                   = var.region
  network                  = google_compute_network.main.id
  ip_cidr_range            = var.network_cidrs.workload
  private_ip_google_access = true
  stack_type               = "IPV4_ONLY"

  secondary_ip_range {
    range_name    = local.pod_secondary_range_name
    ip_cidr_range = var.network_cidrs.pods
  }

  secondary_ip_range {
    range_name    = local.service_secondary_range_name
    ip_cidr_range = var.network_cidrs.services
  }
}

resource "google_compute_router" "main" {
  project = var.project_id
  name    = "${var.name_prefix}-router"
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "main" {
  project                            = var.project_id
  name                               = "${var.name_prefix}-nat"
  region                             = var.region
  router                             = google_compute_router.main.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.management.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  subnetwork {
    name                    = google_compute_subnetwork.workload.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}
