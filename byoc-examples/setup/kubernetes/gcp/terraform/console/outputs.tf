output "endpoint" {
  description = "Public AutoMQ Console endpoint."
  value       = "http://${google_compute_address.console.address}:8080"
}

output "initial_password" {
  description = "Initial AutoMQ Console password."
  value       = random_password.initial_password.result
  sensitive   = true
}

output "initial_access_key" {
  description = "Access key ID for the AutoMQ Terraform provider."
  value       = random_password.access_key.result
  sensitive   = true
}

output "initial_secret_key" {
  description = "Secret key for the AutoMQ Terraform provider."
  value       = random_password.secret_key.result
  sensitive   = true
}

output "service_account_email" {
  description = "Email address of the Console service account."
  value       = google_service_account.console.email
}

output "vm_name" {
  description = "AutoMQ Console VM name."
  value       = google_compute_instance.console.name
}
