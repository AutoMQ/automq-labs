# Fill in your environment-specific values here
# DO NOT COMMIT real secrets to VCS. Keep this file local.

# AWS networking
vpc_id = "vpc-id"
region = "us-east-1"
az     = "us-east-1a"

# AutoMQ BYOC endpoint and credentials
automq_byoc_endpoint      = "http://example.com"
automq_byoc_access_key_id = "access-key"
automq_byoc_secret_key    = "secretkey"

# AutoMQ environment id
automq_environment_id = "automqlab-id"

# Prometheus Integration Configuration
prometheus_integration_name      = "prometheus-remote-write"
prometheus_integration_type      = "prometheusRemoteWrite"
prometheus_remote_write_endpoint = "http://prometheus-kube-prometheus-prometheus.monitoring:9090/api/v1/write"
prometheus_auth_type             = "noauth"

# AutoMQ Deploy Profile Configuration
automq_deploy_profile_name = "eks"

# Kafka Instance Configuration
kafka_instance_name        = "automq-kafka-benchmark"
kafka_instance_description = "AutoMQ Kafka instance for benchmark testing"
kafka_version              = "1.4.1"
kafka_reserved_aku         = 3
kubernetes_node_group_id   = "automq-node-group"
kafka_wal_mode             = "EBSWAL"

# Kafka Authentication and Encryption
kafka_authentication_methods   = ["anonymous"]
kafka_transit_encryption_modes = ["plaintext"]

# Kafka Instance Configuration Parameters
kafka_instance_configs = {
  "auto.create.topics.enable" = "false"
  "log.retention.ms"          = "3600000"
}