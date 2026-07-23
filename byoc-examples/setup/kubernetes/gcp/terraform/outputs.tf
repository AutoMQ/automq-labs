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

output "console_endpoint" {
  description = "Public endpoint for the AutoMQ BYOC Console."
  value       = module.console.endpoint
}

output "console_initial_password" {
  description = "Initial password for the AutoMQ BYOC Console."
  value       = module.console.initial_password
  sensitive   = true
}

output "console_initial_access_key" {
  description = "Access key ID for the AutoMQ Terraform provider."
  value       = module.console.initial_access_key
  sensitive   = true
}

output "console_initial_secret_key" {
  description = "Secret key for the AutoMQ Terraform provider."
  value       = module.console.initial_secret_key
  sensitive   = true
}

output "console_service_account_email" {
  description = "Email address of the service account used by the AutoMQ Console VM."
  value       = module.console.service_account_email
}

output "automq_environment_id" {
  description = "AutoMQ BYOC environment ID used by the Console and Terraform provider."
  value       = local.automq_environment_id
}

output "console_vm_name" {
  description = "AutoMQ Console VM name."
  value       = module.console.vm_name
}
