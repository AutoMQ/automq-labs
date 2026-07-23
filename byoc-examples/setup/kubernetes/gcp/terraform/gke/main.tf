locals {
  automq_network_tag = "${var.name_prefix}-automq-workload"
}

resource "google_container_cluster" "main" {
  project                  = var.project_id
  name                     = "${var.name_prefix}-gke"
  location                 = var.region
  node_locations           = var.zones
  network                  = var.network_id
  subnetwork               = var.workload_subnet_id
  initial_node_count       = 1
  deletion_protection      = false
  networking_mode          = "VPC_NATIVE"
  enable_l4_ilb_subsetting = true

  release_channel {
    channel = "STABLE"
  }

  addons_config {
    dns_cache_config {
      enabled = true
    }

    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  datapath_provider = "ADVANCED_DATAPATH"

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pod_secondary_range_name
    services_secondary_range_name = var.service_secondary_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  node_config {
    machine_type = "n2d-standard-4"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  lifecycle {
    precondition {
      condition     = alltrue([for zone in var.zones : startswith(zone, "${var.region}-")])
      error_message = "Every zone must belong to the selected region."
    }
  }
}

resource "google_container_node_pool" "automq" {
  project            = var.project_id
  name               = "${var.name_prefix}-automq"
  location           = var.region
  node_locations     = var.zones
  cluster            = google_container_cluster.main.name
  initial_node_count = 1

  node_config {
    machine_type = var.automq_node_pool.machine_type
    disk_type    = "hyperdisk-balanced"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    tags         = [local.automq_network_tag]

    labels = {
      node_type = "automq"
    }

    taint {
      key    = "dedicated"
      value  = "automq"
      effect = "NO_SCHEDULE"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  autoscaling {
    total_min_node_count = var.automq_node_pool.min_size
    total_max_node_count = var.automq_node_pool.max_size
    location_policy      = "BALANCED"
  }

  management {
    auto_repair  = false
    auto_upgrade = true
  }
}
