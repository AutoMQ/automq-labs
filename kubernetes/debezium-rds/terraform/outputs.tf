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

output "debezium_setup_instructions" {
  value = <<EOF
To complete Debezium setup for PostgreSQL:

1. Connect to the database:
   psql -h ${aws_db_instance.main.address} -p ${aws_db_instance.main.port} -U ${aws_db_instance.main.username} -d testdb

2. Run the setup script:
   \i setup_debezium_user.sql

3. Use these connection details for Debezium:
   - Host: ${aws_db_instance.main.address}
   - Port: ${aws_db_instance.main.port}
   - Database: testdb
   - Username: debezium (after running setup script)
   - Password: debezium_password_change_me (change as needed)

4. Verify configuration:
   SHOW rds.logical_replication; -- Should be 'on'
   SHOW max_replication_slots;   -- Should be 20
   SHOW max_wal_senders;         -- Should be 20
EOF
}
