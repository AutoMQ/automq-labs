output "eks_cluster_name" {
  value = local.cluster_name
}

output "vpc_id" {
  value = local.vpc_id
}

output "subnet_ids" {
  value = [for id in local.private_subnet_ids : id]
}

output "aws_eks_node_group_role_name" {
  value = aws_iam_role.node_group_role.name
}

output "aws_eks_node_group_role_arn" {
  value = aws_iam_role.node_group_role.arn
}

output "eks_cluster_security_group" {
  value = module.eks.cluster_primary_security_group_id
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_cluster_ca_certificate" {
  value = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

# EKS Addons outputs
output "cluster_autoscaler_role_arn" {
  description = "ARN of the Cluster Autoscaler IAM role"
  value       = module.eks_addons.cluster_autoscaler_role_arn
}

output "alb_controller_role_arn" {
  description = "ARN of the ALB Controller IAM role"
  value       = module.eks_addons.alb_controller_role_arn
}

output "ebs_csi_role_arn" {
  description = "ARN of the EBS CSI IAM role"
  value       = module.eks_addons.ebs_csi_role_arn
}

output "cluster_autoscaler_helm_release_status" {
  description = "Status of the Cluster Autoscaler Helm release"
  value       = module.eks_addons.cluster_autoscaler_helm_release_status
}

output "alb_controller_helm_release_status" {
  description = "Status of the ALB Controller Helm release"
  value       = module.eks_addons.alb_controller_helm_release_status
}
