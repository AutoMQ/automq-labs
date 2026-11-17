output "region" { value = local.region }
output "account_id" { value = data.aws_caller_identity.current.account_id }
output "environment_id" { value = local.environment_id }
output "ops_bucket_name" { value = aws_s3_bucket.ops.id }
output "vpc_id" { value = var.vpc_id }
output "private_subnet_ids_by_az" { value = var.private_subnet_ids_by_az }
output "s3_vpc_endpoint_id" { value = var.s3_vpc_endpoint_id }
output "cluster_name" { value = module.eks_cluster.eks_cluster_name }
output "cluster_endpoint" { value = module.eks_cluster.eks_cluster_endpoint }
output "cluster_certificate_authority_data" { value = module.eks_cluster.eks_cluster_ca_certificate }
output "oidc_provider_arn" { value = module.eks_cluster.oidc_provider_arn }
output "console_namespace" { value = var.console_namespace }
output "console_service_account_name" { value = var.console_service_account_name }
output "console_role_arn" { value = aws_iam_role.pod["console"].arn }
output "ebs_csi_role_arn" { value = module.eks_cluster.component_role_arns["ebs-csi"] }
output "lb_controller_role_arn" { value = module.eks_cluster.component_role_arns["lb-controller"] }
output "autoscaler_role_arn" { value = module.eks_cluster.component_role_arns["autoscaler"] }
output "automq_node_selector" { value = local.automq_selector }
output "automq_tolerations" { value = local.automq_tolerations }
output "node_role_arn" { value = module.eks_cluster.node_role_arn }
output "kubernetes_version" { value = var.kubernetes_version }
output "deployer_role_arn" { value = var.deployer_role_arn }
output "private_nat_gateway_id" {
  description = "NAT owned by this example when explicitly enabled; destroy only after dependent workloads."
  value       = try(aws_nat_gateway.private[0].id, null)
}
output "addon_versions" {
  description = "Resolved versions; supply these as addon_versions when reproducing the verified matrix."
  value       = module.eks_cluster.addon_versions
}

output "console_kubernetes_access" {
  description = "Console IAM authentication to EKS, ready before installing the Console release."
  value = {
    principal_arn = aws_eks_access_entry.console.principal_arn
    policy_arn    = aws_eks_access_policy_association.console.policy_arn
    scope_type    = aws_eks_access_policy_association.console.access_scope[0].type
  }
}
