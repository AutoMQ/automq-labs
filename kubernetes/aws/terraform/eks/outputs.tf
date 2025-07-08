output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "vpc_id" {
    value = local.vpc_id
}

output "subnet_ids" {
    value = [for id in local.private_subnet_ids : id]
}

output "eks_cluster_security_group" {
    value = module.eks.cluster_primary_security_group_id
}

output "aws_eks_node_group_role_name" {
    value = aws_iam_role.nodes.name
}

output "aws_eks_node_group_role_arn" {
    value = aws_iam_role.nodes.arn
}
