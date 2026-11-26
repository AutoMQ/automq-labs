resource "google_project_service" "iam_credentials" {
  depends_on = [terraform_data.preflight]

  project            = local.gke_project_id
  service            = "iamcredentials.googleapis.com"
  disable_on_destroy = false
}

locals {
  worker_service_account_id = var.worker_service_account_id != null ? var.worker_service_account_id : trim(
    substr("${var.connect_cluster_name}-worker", 0, 30), "-",
  )
}

resource "google_service_account" "connect_worker" {
  depends_on = [terraform_data.preflight, google_project_service.iam_credentials]

  project      = local.gke_project_id
  account_id   = local.worker_service_account_id
  display_name = "AutoMQ Connect worker: ${var.connect_cluster_name}"
}

resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.connect_worker.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${coalesce(local.workload_identity_pool, "${local.gke_project_id}.svc.id.goog")}[${var.connect_namespace}/${var.connect_service_account}]"
}

# The Console automatically configures worker logs and metrics in this bucket.
# The built-in MySQL plugin itself is downloaded from its HTTPS catalog URL.
resource "google_storage_bucket_iam_member" "ops" {
  depends_on = [terraform_data.preflight]

  bucket = local.ops_bucket_name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.connect_worker.email}"
}

resource "time_sleep" "workload_identity" {
  depends_on = [
    google_service_account_iam_member.workload_identity,
    google_storage_bucket_iam_member.ops,
    kubernetes_service_account_v1.connect,
  ]

  # Best-effort IAM propagation buffer; worker readiness is checked by Console.
  create_duration = "60s"
  triggers = {
    service_account_id = google_service_account.connect_worker.name
    identity_member    = google_service_account_iam_member.workload_identity.member
    ops_bucket_name    = local.ops_bucket_name
  }
}
