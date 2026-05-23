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

output "data_bucket" {
  description = "Data bucket name for the AutoMQ BYOC environment"
  value       = "automq-data-${module.automq-byoc.automq_byoc_env_id}"
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks-env.cluster_name
}

output "region" {
  description = "AWS region where resources are deployed"
  value       = var.region
}

output "vpc_id" {
  description = "VPC ID used by the EKS environment"
  value       = module.eks-env.vpc_id
}

output "default_az" {
  description = "Selected availability zone (first private subnet AZ)"
  value       = module.eks-env.azs[0]

}

output "automq_environment_id" {
  description = "AutoMQ Environment ID used for BYOC"
  value       = module.automq-byoc.automq_byoc_env_id
}

output "node_group_instance_profile_arn" {
  description = "ARN of the EKS Node Group"
  value       = module.eks-env.node_group_instance_profile_arn
}


