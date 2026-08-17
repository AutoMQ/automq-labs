output "environment_id" {
  description = "AutoMQ BYOC environment ID decoded from CONFIG"
  value       = local.environment_id
}

output "region" {
  description = "AWS Region decoded from CONFIG"
  value       = local.region
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
  description = "Generated initial Console password"
  value       = random_password.console_initial_password.result
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

output "console_allowed_cidr_blocks" {
  description = "CIDRs allowed to reach the Console"
  value       = local.console_allowed_cidr_blocks
}

output "console_role_arn" {
  description = "IAM Role ARN attached to the Console EC2 instance"
  value       = aws_iam_role.console.arn
}

output "cluster_role_arn" {
  description = "IAM Role ARN used for iam:PassRole and policy review"
  value       = module.automq_role.role_arn
}

output "cluster_role_name" {
  description = "IAM Role name to pass to the AutoMQ IAAS Cluster"
  value       = module.automq_role.role_name
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
  description = "S3 ops bucket decoded from CONFIG and created by this root"
  value       = local.ops_bucket_name
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
  value       = aws_vpc.this.id
}

output "public_subnet_id" {
  description = "Public subnet containing the AutoMQ Console"
  value       = aws_subnet.console.id
}

output "private_subnet_ids_by_zone" {
  description = "Private broker subnet IDs keyed by availability zone"
  value       = local.private_subnet_ids_by_zone
}

output "broker_networks" {
  description = "AutoMQ Provider network payload for the Cluster stage"
  value       = local.broker_networks
}

output "console_ami_id" {
  description = "Resolved Amazon Linux 2023 AMI ID"
  value       = nonsensitive(data.aws_ssm_parameter.al2023_ami.value)
}

output "console_image" {
  description = "AutoMQ BYOC Console image"
  value       = var.console_image
}
