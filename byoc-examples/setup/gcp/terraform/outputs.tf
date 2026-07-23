output "project_id" {
  description = "GCP project containing the Console resources."
  value       = var.project_id
}

output "region" {
  description = "GCP region containing the Console resources."
  value       = var.region
}

output "zone" {
  description = "GCP zone containing the Console VM."
  value       = var.zone
}

output "network_id" {
  description = "Canonical VPC resource ID used by the Console."
  value       = var.network_id
}

output "management_subnet_id" {
  description = "Canonical subnet resource ID used by the Console."
  value       = var.management_subnet_id
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
