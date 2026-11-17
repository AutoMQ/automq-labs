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
  value       = try(aws_iam_role.pod["autoscaler"].arn, try(module.eks_addons[0].cluster_autoscaler_role_arn, null))
}

output "alb_controller_role_arn" {
  description = "ARN of the ALB Controller IAM role"
  value       = try(aws_iam_role.pod["lb-controller"].arn, try(module.eks_addons[0].alb_controller_role_arn, null))
}

output "ebs_csi_role_arn" {
  description = "ARN of the EBS CSI IAM role"
  value       = try(aws_iam_role.pod["ebs-csi"].arn, try(module.eks_addons[0].ebs_csi_role_arn, null))
}

output "cluster_autoscaler_helm_release_status" {
  description = "Status of the Cluster Autoscaler Helm release"
  value       = try(module.eks_addons[0].cluster_autoscaler_helm_release_status, "disabled")
}

output "alb_controller_helm_release_status" {
  description = "Status of the ALB Controller Helm release"
  value       = try(module.eks_addons[0].alb_controller_helm_release_status, "disabled")
}

output "cluster_name" {
  description = "EKS cluster name; alias for eks_cluster_name."
  value       = module.eks.cluster_name
}

output "cluster_oidc_issuer_url" {
  description = "Issuer URL for callers creating their own Pod roles."
  value       = module.eks.cluster_oidc_issuer_url
}

output "node_role_arn" {
  description = "Node role; alias for aws_eks_node_group_role_arn."
  value       = aws_iam_role.node_group_role.arn
}

output "component_role_arns" {
  description = "Independent infrastructure Pod roles; empty unless component_irsa_prefix is set."
  value       = { for name, role in aws_iam_role.pod : name => role.arn }
}

output "node_group_names" {
  description = "System and additional workload node group names."
  value       = merge({ system = aws_eks_node_group.system_nodes.node_group_name }, { for key, pool in aws_eks_node_group.workload : key => pool.node_group_name })
}

output "addon_versions" {
  description = "Selected core managed-addon versions when manage_core_addons is enabled."
  value       = { for name, addon in data.aws_eks_addon_version.this : name => lookup(var.addon_versions, name, addon.version) }
}
