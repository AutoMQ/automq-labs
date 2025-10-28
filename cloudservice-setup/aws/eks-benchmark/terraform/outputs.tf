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

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks-env.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks-env.cluster_security_group_id
}

output "cluster_iam_role_name" {
  description = "IAM role name associated with EKS cluster"
  value       = module.eks-env.cluster_iam_role_name
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN associated with EKS cluster"
  value       = module.eks-env.cluster_iam_role_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks-env.cluster_certificate_authority_data
}

output "cluster_version" {
  description = "The Kubernetes version for the EKS cluster"
  value       = module.eks-env.cluster_version
}

output "node_groups" {
  description = "EKS node groups"
  value       = module.eks-env.node_groups
}

output "fargate_profiles" {
  description = "EKS Fargate profiles"
  value       = module.eks-env.fargate_profiles
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider if enabled"
  value       = module.eks-env.oidc_provider_arn
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

# Prometheus Outputs
output "prometheus_namespace" {
  description = "Kubernetes namespace where Prometheus is deployed"
  value       = var.enable_prometheus ? helm_release.prometheus[0].namespace : null
}

output "prometheus_release_name" {
  description = "Helm release name for Prometheus"
  value       = var.enable_prometheus ? helm_release.prometheus[0].name : null
}

output "prometheus_chart_version" {
  description = "Version of the Prometheus Helm chart deployed"
  value       = var.enable_prometheus ? helm_release.prometheus[0].version : null
}

