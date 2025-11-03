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

# Benchmark Node Group Outputs
output "benchmark_node_group_name" {
  description = "Name of the benchmark node group"
  value       = var.enable_benchmark_nodes ? aws_eks_node_group.benchmark_node_group[0].node_group_name : null
}

output "benchmark_node_group_arn" {
  description = "ARN of the benchmark node group"
  value       = var.enable_benchmark_nodes ? aws_eks_node_group.benchmark_node_group[0].arn : null
}



output "automq_control_panel_env_id" {
  description = "environment id of control panel"
  value       = module.automq-byoc.automq_byoc_env_id
}

output "benchmark_node_group_status" {
  description = "Status of the benchmark node group"
  value       = var.enable_benchmark_nodes ? aws_eks_node_group.benchmark_node_group[0].status : null
}

output "benchmark_node_group_capacity_type" {
  description = "Type of capacity associated with the benchmark EKS Node Group"
  value       = var.enable_benchmark_nodes ? aws_eks_node_group.benchmark_node_group[0].capacity_type : null
}

output "benchmark_node_group_instance_types" {
  description = "Set of instance types associated with the benchmark EKS Node Group"
  value       = var.enable_benchmark_nodes ? aws_eks_node_group.benchmark_node_group[0].instance_types : null
}

output "benchmark_node_group_scaling_config" {
  description = "Configuration block with scaling settings for the benchmark node group"
  value       = var.enable_benchmark_nodes ? aws_eks_node_group.benchmark_node_group[0].scaling_config : null
}

output "benchmark_node_group_labels" {
  description = "Key-value map of Kubernetes labels applied to the benchmark nodes"
  value       = var.enable_benchmark_nodes ? aws_eks_node_group.benchmark_node_group[0].labels : null
}

output "benchmark_tolerations" {
  description = "Tolerations to use when scheduling workloads on dedicated benchmark nodes"
  value = var.enable_benchmark_nodes && var.benchmark_enable_dedicated_nodes ? [
    {
      key      = "benchmark-node"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    }
  ] : null
}

output "node_group_instance_profile_arn" {
  description = "ARN of the EKS Node Group"
  value       = module.eks-env.node_group_instance_profile_arn
}


