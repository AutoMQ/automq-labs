output "database_endpoint" {
  value = aws_db_instance.main.address
}

output "database_port" {
  value = aws_db_instance.main.port
}

output "database_username" {
  value = aws_db_instance.main.username
}

output "database_password" {
  value     = random_password.db.result
  sensitive = true
}

output "connection_string" {
  value     = "${var.database_type}://${aws_db_instance.main.username}:${random_password.db.result}@${aws_db_instance.main.address}:${aws_db_instance.main.port}/testdb"
  sensitive = true
}
