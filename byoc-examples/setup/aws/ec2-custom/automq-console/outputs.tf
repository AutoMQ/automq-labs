output "environment_id" {
  description = "AutoMQ BYOC environment ID"
  value       = var.environment_id
}

output "console_endpoint" {
  description = "Public AutoMQ Console endpoint"
  value       = "http://${aws_eip.console.public_ip}:8080"
}

output "console_initial_username" {
  description = "Initial Console username"
  value       = "admin"
}

output "console_initial_password" {
  description = "Initial Console password; the AMI uses the EC2 instance ID"
  value       = aws_instance.console.id
  sensitive   = true
}

output "console_initial_access_key" {
  description = "Access key used by the AutoMQ Provider"
  value       = random_password.console_initial_access_key.result
  sensitive   = true
}

output "console_initial_secret_key" {
  description = "Secret key used by the AutoMQ Provider"
  value       = random_password.console_initial_secret_key.result
  sensitive   = true
}

output "console_instance_id" {
  description = "AutoMQ Console EC2 instance ID"
  value       = aws_instance.console.id
}

output "console_security_group_id" {
  description = "AutoMQ Console security group ID"
  value       = aws_security_group.console.id
}

output "console_role_arn" {
  description = "IAM Role ARN attached to the Console EC2 instance"
  value       = aws_iam_role.console.arn
}

output "console_private_key_path" {
  description = "Local path containing the generated Console SSH key"
  value       = local_sensitive_file.console_private_key.filename
}

output "console_private_key_pem" {
  description = "Generated Console SSH private key"
  value       = tls_private_key.console.private_key_pem
  sensitive   = true
}

output "cluster_role_arn" {
  description = "IAM Role ARN to pass to the AutoMQ IAAS Cluster"
  value       = module.automq_role.role_arn
}

output "cluster_instance_profile_arn" {
  description = "IAM Instance Profile ARN used by AutoMQ EC2 nodes"
  value       = module.automq_role.instance_profile_arn
}

output "data_bucket_name" {
  description = "S3 data bucket passed to the AutoMQ IAAS Cluster"
  value       = local.data_bucket_name
}

output "ops_bucket_name" {
  description = "S3 ops bucket used by the AutoMQ Console and data plane"
  value       = var.ops_bucket_name
}

output "dns_zone_id" {
  description = "Private Route 53 hosted zone ID passed to the AutoMQ IAAS Cluster"
  value       = aws_route53_zone.private.zone_id
}

output "dns_zone_name" {
  description = "Private Route 53 hosted zone name"
  value       = aws_route53_zone.private.name
}

output "vpc_id" {
  description = "VPC containing the AutoMQ environment"
  value       = var.vpc_id
}

output "private_subnet_ids_by_zone" {
  description = "Private broker subnet IDs keyed by availability zone"
  value       = var.private_subnet_ids_by_zone
}

output "broker_networks" {
  description = "AutoMQ Provider network payload for the Cluster stage"
  value       = local.broker_networks
}

output "console_ami_id" {
  description = "Resolved AutoMQ Console AMI ID"
  value       = data.aws_ami.console.id
}
