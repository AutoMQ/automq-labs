output "cluster_id" {
  description = "Canonical GKE cluster resource ID."
  value       = google_container_cluster.main.id
}

output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.main.name
}

output "automq_node_pool_name" {
  description = "Name of the dedicated AutoMQ workload node pool."
  value       = google_container_node_pool.automq.name
}

output "automq_network_tag" {
  description = "Network tag applied to AutoMQ workload nodes."
  value       = local.automq_network_tag
}

output "workload_identity_pool" {
  description = "Workload Identity pool configured on the GKE cluster."
  value       = google_container_cluster.main.workload_identity_config[0].workload_pool
}
