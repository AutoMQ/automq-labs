output "instance_id" {
  description = "AutoMQ Kafka Instance ID"
  value       = automq_kafka_instance.this.id
}

output "instance_status" {
  description = "AutoMQ Kafka Instance provisioning status"
  value       = automq_kafka_instance.this.status
}

output "instance_endpoints" {
  description = "Kafka client endpoints"
  value       = automq_kafka_instance.this.endpoints
}

output "broker_networks" {
  description = "Deterministically ordered network payload used for the IAAS Instance"
  value       = local.broker_networks
}
