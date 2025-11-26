
output "env_id" {
  value = local.env_id
}

output "console_endpoint" {
  value = "http://${aws_eip.web_ip.public_ip}:8080"
}

output "console_initial_username" {
  value = "admin"
}

output "console_initial_password" {
  value     = aws_instance.automq_byoc_console.id
  sensitive = true
}

output "private_key_pem" {
  sensitive = true
  value     = tls_private_key.key_pair.private_key_pem
}

output "data_bucket" {
  value = local.data_bucket_name
}

output "ops_bucket" {
  value = local.ops_bucket_name
}
