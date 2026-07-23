locals {
  resource_prefix = "${var.name_prefix}-console"

  service_account_id = trim(substr("${local.resource_prefix}-sa", 0, 30), "-")

  labels = {
    automq_vendor = "automq"
    component     = "console"
  }

  runtime_roles = toset([
    "roles/container.admin",
    "roles/compute.networkViewer",
    "roles/dns.admin",
    "roles/iam.roleAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/storage.admin",
  ])
}

resource "google_service_account" "console" {
  project      = var.project_id
  account_id   = local.service_account_id
  display_name = "AutoMQ BYOC Console"
}

resource "google_project_iam_member" "console" {
  for_each = local.runtime_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.console.email}"
}

resource "google_project_iam_custom_role" "dns_iam_admin" {
  project     = var.project_id
  role_id     = "automqByocConsoleDnsZoneIamPolicyAdmin"
  title       = "AutoMQ Console DNS Zone IAM Policy Admin"
  description = "Allows the AutoMQ Console to update IAM policy on Cloud DNS managed zones"
  permissions = [
    "dns.managedZones.getIamPolicy",
    "dns.managedZones.setIamPolicy",
  ]
}

resource "google_project_iam_member" "console_dns_iam_admin" {
  project = var.project_id
  role    = google_project_iam_custom_role.dns_iam_admin.name
  member  = "serviceAccount:${google_service_account.console.email}"
}

resource "google_compute_address" "console" {
  project = var.project_id
  name    = "${local.resource_prefix}-ip"
  region  = var.region
}

resource "google_compute_disk" "console" {
  project = var.project_id
  name    = "${local.resource_prefix}-data"
  zone    = var.zone
  type    = "pd-ssd"
  size    = 20
  labels  = local.labels
}

resource "google_compute_firewall" "console" {
  project = var.project_id
  name    = "${local.resource_prefix}-ingress"
  network = var.network_id

  direction     = "INGRESS"
  source_ranges = var.ingress_source_ranges

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  target_service_accounts = [google_service_account.console.email]
}

resource "random_password" "initial_password" {
  length  = 24
  special = false
}

resource "random_password" "access_key" {
  length  = 16
  special = false
}

resource "random_password" "secret_key" {
  length  = 32
  special = false
}

resource "random_id" "console_bootstrap" {
  byte_length = 1

  keepers = {
    configuration = sha256(jsonencode({
      console_image = var.console_image
      config        = var.config
      home_endpoint = var.home_endpoint
      registry      = var.registry
    }))
  }
}

resource "google_compute_instance" "console" {
  project      = var.project_id
  name         = local.resource_prefix
  machine_type = var.machine_type
  zone         = var.zone
  labels       = local.labels

  boot_disk {
    initialize_params {
      image = "projects/debian-cloud/global/images/family/debian-12"
      size  = 30
      type  = "pd-balanced"
    }
  }

  attached_disk {
    source      = google_compute_disk.console.id
    device_name = "automq-console-data"
    mode        = "READ_WRITE"
  }

  network_interface {
    subnetwork = var.management_subnet_id

    access_config {
      nat_ip = google_compute_address.console.address
    }
  }

  metadata_startup_script = templatefile("${path.module}/startup.sh.tpl", {
    console_image_b64     = base64encode(var.console_image)
    config_b64            = base64encode(var.config)
    home_endpoint_b64     = base64encode(var.home_endpoint)
    initial_password_b64  = base64encode(random_password.initial_password.result)
    access_key_b64        = base64encode(random_password.access_key.result)
    secret_key_b64        = base64encode(random_password.secret_key.result)
    service_account_b64   = base64encode(google_service_account.console.email)
    registry_server_b64   = base64encode(var.registry.server)
    registry_username_b64 = base64encode(var.registry.username)
    registry_password_b64 = base64encode(var.registry.password)
  })

  service_account {
    email  = google_service_account.console.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  lifecycle {
    replace_triggered_by = [random_id.console_bootstrap]
  }

  allow_stopping_for_update = true

  depends_on = [
    google_compute_firewall.console,
    google_project_iam_member.console,
    google_project_iam_member.console_dns_iam_admin,
  ]
}
