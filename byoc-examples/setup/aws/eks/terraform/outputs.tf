output "console_endpoint" {
  description = "Console endpoint for the AutoMQ BYOC environment"
  value       = "https://${var.automq_console_domain_name}"
}

output "initial_username" {
  description = "Initial username for the AutoMQ BYOC environment"
  value       = "admin"
}

output "initial_password" {
  description = "Initial password for the AutoMQ BYOC environment"
  value       = "admin"
  sensitive   = true
}

output "cluster_name" {
  description = "EKS Cluster Name"
  value       = module.eks-env.cluster_name
}

output "node_group_instance_profile_arn" {
  description = "ARN of the EKS Node Group"
  value       = module.eks-env.node_group_instance_profile_arn
}
