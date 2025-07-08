output "node_group_role_arn" {
  description = "EKS Node Group Role ARN"
  value       = aws_iam_role.node_group_role.arn
}

output "policy_name" {
  description = "EKS Node Group Policy Name"
  value       = aws_iam_policy.custom_policy.name
  depends_on  = [aws_iam_policy.custom_policy]
}

output "node_group_role_name" {
  description = "EKS Node Group Role Name"
  value       = aws_iam_role.node_group_role.name
  depends_on  = [aws_iam_role.node_group_role]
}

output "node_group_instance_profile_arn" {
  description = "EKS Node Group Instance Profile ARN"
  value       = aws_iam_instance_profile.node_group_instance_profile.arn
  depends_on  = [aws_iam_instance_profile.node_group_instance_profile]
}
