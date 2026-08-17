output "role_arn" {
  description = "IAM Role ARN passed to the AutoMQ IAAS cluster"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "IAM Role name for AutoMQ EC2 nodes"
  value       = aws_iam_role.this.name
}

output "instance_profile_arn" {
  description = "IAM Instance Profile ARN for AutoMQ EC2 nodes"
  value       = aws_iam_instance_profile.this.arn
}

output "instance_profile_name" {
  description = "IAM Instance Profile name for AutoMQ EC2 nodes"
  value       = aws_iam_instance_profile.this.name
}

output "policy_json" {
  description = "Rendered data-plane IAM policy for contract testing and review"
  value       = jsonencode(local.policy_document)
}
