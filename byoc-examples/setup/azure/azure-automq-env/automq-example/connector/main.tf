terraform {
  required_version = ">= 1.3"

  required_providers {
    automq = {
      source  = "automq/automq"
      version = "= 0.4.8"
    }
  }
}

provider "automq" {}

variable "environment_id" {
  type        = string
  description = "ID of the existing Azure BYOC environment."
}

variable "kafka_instance_id" {
  type        = string
  description = "Kafka Instance ID from the Instance example."
}

variable "kubernetes_cluster_id" {
  type        = string
  description = "Full ARM resource ID of the existing AKS cluster."
}

variable "node_pool_name" {
  type        = string
  description = "Name of the existing AutoMQ AKS node pool."
}

variable "plugin_storage_url" {
  type        = string
  description = "Accessible HTTPS URL of the complete Datagen plugin ZIP."
}

variable "plugin_version" {
  type        = string
  description = "Datagen plugin version matching the archive."
}

variable "connect_namespace" {
  type        = string
  description = "Kubernetes namespace for Connect workers."
}

variable "connect_service_account" {
  type        = string
  description = "Kubernetes ServiceAccount for Connect workers."
}

variable "kafka_password" {
  type        = string
  description = "SASL password for the datagen-writer Kafka user."
  sensitive   = true
}

resource "automq_kafka_topic" "orders" {
  environment_id    = var.environment_id
  kafka_instance_id = var.kafka_instance_id
  name              = "orders"
  partition         = 3
}

# Kafka SASL credentials are separate from the AutoMQ API Service Account.
resource "automq_kafka_user" "datagen" {
  environment_id    = var.environment_id
  kafka_instance_id = var.kafka_instance_id
  username          = "datagen-writer"
  password          = var.kafka_password
}

resource "automq_kafka_acl" "produce_orders" {
  environment_id    = var.environment_id
  kafka_instance_id = var.kafka_instance_id
  resource_type     = "TOPIC"
  resource_name     = automq_kafka_topic.orders.name
  pattern_type      = "LITERAL"
  principal         = "User:${automq_kafka_user.datagen.username}"
  operation_group   = "PRODUCE"
  permission        = "ALLOW"
}

# Register an existing plugin archive compatible with the Connect runtime.
# This resource does not build or upload the archive.
resource "automq_connector_plugin" "datagen" {
  environment_id  = var.environment_id
  name            = "demo-datagen"
  version         = var.plugin_version
  storage_url     = var.plugin_storage_url
  types           = ["SOURCE"]
  connector_class = "io.confluent.kafka.connect.datagen.DatagenConnector"
}

resource "automq_connect_cluster" "demo" {
  environment_id = var.environment_id
  name           = "azure-connect-demo"
  kafka_cluster = {
    kafka_instance_id = var.kafka_instance_id
  }
  plugins = [{
    name    = automq_connector_plugin.datagen.name
    version = automq_connector_plugin.datagen.version
  }]
  capacity = {
    type = "provisioned"
    provisioned = {
      worker_count         = 1
      worker_resource_spec = "TIER1"
    }
  }
  compute = {
    type = "k8s"
    kubernetes = {
      cluster_id      = var.kubernetes_cluster_id
      namespace       = var.connect_namespace
      service_account = var.connect_service_account
      scheduling_spec = yamlencode({
        nodeSelector = {
          "kubernetes.azure.com/agentpool" = var.node_pool_name
        }
        tolerations = [{
          key      = "dedicated"
          operator = "Equal"
          value    = "automq"
          effect   = "NoSchedule"
        }]
      })
    }
  }
  worker_config = {
    "key.converter"                  = "org.apache.kafka.connect.storage.StringConverter"
    "value.converter"                = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter.schemas.enable" = "false"
  }
}

resource "automq_connector" "orders" {
  environment_id     = var.environment_id
  connect_cluster_id = automq_connect_cluster.demo.id
  name               = "demo-orders-datagen"
  connector_class    = automq_connector_plugin.datagen.connector_class
  task_count         = 1
  kafka_cluster = {
    security_protocol = {
      protocol       = "SASL_PLAINTEXT"
      username       = automq_kafka_user.datagen.username
      password       = var.kafka_password
      sasl_mechanism = "SCRAM-SHA-512"
    }
  }
  connector_config = {
    "kafka.topic"  = automq_kafka_topic.orders.name
    "quickstart"   = "orders"
    "max.interval" = "1000"
    # Use a non-idempotent producer for this basic topic-level ACL example.
    "producer.override.enable.idempotence" = "false"
  }
  depends_on = [automq_kafka_acl.produce_orders]
}

output "connect_cluster_id" {
  value = automq_connect_cluster.demo.id
}

output "connector_id" {
  value = automq_connector.orders.id
}

output "connector_state" {
  value = automq_connector.orders.state
}
