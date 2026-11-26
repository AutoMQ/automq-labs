output "environment_id" {
  description = "AutoMQ environment read from the Console state."
  value       = local.environment_id
}

output "kafka_instance_id" {
  description = "Existing AutoMQ Instance associated with the Connect Cluster."
  value       = local.kafka_instance_id
}

output "connect_cluster_id" {
  description = "AutoMQ Connect Cluster ID."
  value       = automq_connect_cluster.demo.id
}

output "connect_cluster_state" {
  description = "Connect Cluster lifecycle state reported by AutoMQ."
  value       = automq_connect_cluster.demo.state
}

output "kubernetes_cluster_id" {
  description = "Externally supplied GKE resource ID."
  value       = var.kubernetes_cluster_id
}

output "connect_namespace" {
  description = "Dedicated namespace managed by this example."
  value       = kubernetes_namespace_v1.connect.metadata[0].name
}

output "connect_service_account" {
  description = "Kubernetes ServiceAccount linked to the worker Google Service Account."
  value       = kubernetes_service_account_v1.connect.metadata[0].name
}

output "worker_service_account_email" {
  description = "Worker Google Service Account email used in the Kubernetes annotation."
  value       = google_service_account.connect_worker.email
}

output "worker_service_account_id" {
  description = "Full worker Google Service Account resource name passed to Connect."
  value       = google_service_account.connect_worker.name
}

output "ops_bucket_name" {
  description = "Existing environment Ops Bucket receiving the worker's object permissions."
  value       = local.ops_bucket_name
}

output "console_to_workers_firewall" {
  description = "Firewall rule allowing the Console to reach worker REST and metrics ports."
  value       = google_compute_firewall.console_to_workers.name
}
