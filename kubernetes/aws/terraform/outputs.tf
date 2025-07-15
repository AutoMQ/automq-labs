
# Output important configuration values
output "region" {
  description = "AWS region"
  value       = local.region
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "cluster_name" {
  description = "EKS Cluster Name"
  value       = module.eks.eks_cluster_name
}

output "node_group_name" {
  description = "EKS Node Group Name"
  value       = aws_eks_node_group.automq-node-groups.node_group_name
}

output "node_group_instance_profile_arn" {
  description = "ARN of the EKS Node Group IAM Role"
  value       = module.cluster-iam.node_group_instance_profile_arn
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.network.public_subnets
}

output "private_subnets" {
  description = "List of private subnet IDs"
  value       = module.network.private_subnets
}

output "eks_cluster_security_group" {
  description = "Security Group ID for the EKS Cluster"
  value       = module.eks.eks_cluster_security_group
}


