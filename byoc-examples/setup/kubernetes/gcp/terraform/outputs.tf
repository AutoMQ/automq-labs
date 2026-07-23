output "project_id" {
  description = "GCP project containing the provisioned resources."
  value       = var.project_id
}

output "region" {
  description = "GCP region containing the regional GKE cluster."
  value       = var.region
}

output "zones" {
  description = "Zones used by the GKE node pools."
  value       = var.zones
}

output "gke_cluster_id" {
  description = "Canonical GKE cluster resource ID."
  value       = module.gke.cluster_id
}

output "gke_cluster_name" {
  description = "GKE cluster name."
  value       = module.gke.cluster_name
}

output "automq_node_pool_name" {
  description = "Name of the dedicated AutoMQ workload node pool."
  value       = module.gke.automq_node_pool_name
}

output "vpc_id" {
  description = "Canonical VPC resource ID."
  value       = module.network.vpc_id
}

output "management_subnet_id" {
  description = "Canonical management subnet resource ID."
  value       = module.network.management_subnet_id
}

output "workload_subnet_id" {
  description = "Canonical GKE workload subnet resource ID."
  value       = module.network.workload_subnet_id
}

output "workload_identity_pool" {
  description = "Workload Identity pool configured on the GKE cluster."
  value       = module.gke.workload_identity_pool
}

output "get_credentials_command" {
  description = "Command that configures kubectl credentials for the GKE cluster."
  value       = "gcloud container clusters get-credentials ${module.gke.cluster_name} --region ${var.region} --project ${var.project_id}"
}
