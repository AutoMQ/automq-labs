# The cluster and node pool are externally owned; this root only reads them.
data "google_container_cluster" "target" {
  project  = local.gke_project_id
  location = local.gke_location
  name     = local.gke_cluster_name
}

data "google_project" "target" {
  project_id = local.gke_project_id
}

locals {
  connect_node_pool = try(one([
    for pool in data.google_container_cluster.target.node_pool : pool
    if pool.name == var.connect_node_pool_name
  ]), null)
  workload_identity_pool = try(data.google_container_cluster.target.workload_identity_config[0].workload_pool, "")

  node_service_account_raw = try(local.connect_node_pool.node_config[0].service_account, "default")
  node_service_account = contains(["", "default"], local.node_service_account_raw) ? (
    "${data.google_project.target.number}-compute@developer.gserviceaccount.com"
  ) : local.node_service_account_raw

  gke_network = trimprefix(data.google_container_cluster.target.network, "https://www.googleapis.com/compute/v1/")
  gke_network_id = startswith(local.gke_network, "projects/") ? local.gke_network : (
    "projects/${local.gke_project_id}/global/networks/${local.gke_network}"
  )

  # Console 8.4.13 rejects a present-but-empty tolerations list.
  connect_scheduling_spec = yamlencode(merge(
    {
      nodeSelector = { "cloud.google.com/gke-nodepool" = var.connect_node_pool_name }
    },
    length(var.connect_tolerations) > 0 ? { tolerations = var.connect_tolerations } : {},
  ))

  unmatched_node_taints = [
    for taint in try(local.connect_node_pool.node_config[0].taint, []) : taint
    if contains(["NO_SCHEDULE", "NO_EXECUTE"], taint.effect) && !anytrue([
      for toleration in var.connect_tolerations :
      toleration.key == taint.key &&
      (toleration.operator == "Exists" || toleration.value == taint.value) &&
      toleration.effect == lookup({ NO_SCHEDULE = "NoSchedule", NO_EXECUTE = "NoExecute" }, taint.effect, "")
    ])
  ]
}

resource "kubernetes_namespace_v1" "connect" {
  depends_on = [terraform_data.preflight]

  metadata {
    name = var.connect_namespace
    labels = {
      "app.kubernetes.io/part-of" = "automq-connect"
    }
  }
}

resource "kubernetes_service_account_v1" "connect" {
  metadata {
    name      = var.connect_service_account
    namespace = kubernetes_namespace_v1.connect.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.connect_worker.email
    }
  }

  automount_service_account_token = true
}

# Use the node VM identity, not the worker's Workload Identity, as the target.
# Other node pools using the same node VM Service Account also match this rule.
resource "google_compute_firewall" "console_to_workers" {
  depends_on = [terraform_data.preflight]

  project                 = local.gke_project_id
  name                    = "${var.connect_cluster_name}-console-to-workers"
  network                 = local.gke_network_id
  direction               = "INGRESS"
  source_service_accounts = [local.console_service_account_email]
  target_service_accounts = [local.node_service_account]

  allow {
    protocol = "tcp"
    ports    = ["8083", "9090"]
  }
}
