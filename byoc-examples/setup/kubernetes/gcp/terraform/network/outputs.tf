output "vpc_id" {
  description = "Canonical VPC resource ID."
  value       = google_compute_network.main.id
}

output "management_subnet_id" {
  description = "Canonical management subnet resource ID."
  value       = google_compute_subnetwork.management.id
}

output "management_subnet_cidr" {
  description = "Primary CIDR of the management subnet."
  value       = google_compute_subnetwork.management.ip_cidr_range
}

output "workload_subnet_id" {
  description = "Canonical GKE workload subnet resource ID."
  value       = google_compute_subnetwork.workload.id
}

output "workload_subnet_cidr" {
  description = "Primary CIDR of the GKE workload subnet."
  value       = google_compute_subnetwork.workload.ip_cidr_range
}

output "pod_secondary_range_name" {
  description = "Name of the secondary range used for GKE Pods."
  value       = local.pod_secondary_range_name
}

output "service_secondary_range_name" {
  description = "Name of the secondary range used for GKE Services."
  value       = local.service_secondary_range_name
}
