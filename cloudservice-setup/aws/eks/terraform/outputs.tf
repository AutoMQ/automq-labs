output "console_endpoint" {
  description = "Console endpoint for the AutoMQ BYOC environment"
  value       = module.automq-byoc.automq_byoc_endpoint
}

output "initial_username" {
  description = "Initial username for the AutoMQ BYOC environment"
  value       = module.automq-byoc.automq_byoc_initial_username
}

output "initial_password" {
  description = "Initial password for the AutoMQ BYOC environment"
  value       = module.automq-byoc.automq_byoc_initial_password
}

output "dns_zone_id" {
  description = "Route53 DNS Zone ID for the AutoMQ BYOC environment"
  value       = module.automq-byoc.automq_byoc_vpc_route53_zone_id
}

output "cluster_name" {
  description = "EKS Cluster Name"
  value       = module.eks-env.cluster_name
}

output "node_group_instance_profile_arn" {
  description = "ARN of the EKS Node Group"
  value       = module.eks-env.node_group_instance_profile_arn
}
