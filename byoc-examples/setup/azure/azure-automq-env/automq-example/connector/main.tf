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

# Edit environment-specific values here before running this example.
locals {
  environment_id          = "<environment-id>"
  kubernetes_cluster_id   = "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.ContainerService/managedClusters/<aks-name>"
  node_pool_name          = "automq"
  kafka_instance_id       = "<kafka-instance-id>"
  connector_name          = "demo-orders-postgres"
  connect_namespace       = "connect-demo"
  connect_service_account = "connect-demo"
  plugin_version          = "<debezium-jdbc-plugin-version>"
  plugin_storage_url      = "https://<plugin-host>/debezium-connector-jdbc.zip"
  kafka_password          = sensitive("<kafka-user-password>")
  jdbc_url                = "jdbc:postgresql://<database-host>:5432/<database-name>?sslmode=require"
  database_username       = "<database-username>"
  database_password       = sensitive("<database-password>")
}

resource "automq_kafka_topic" "orders" {
  environment_id    = local.environment_id
  kafka_instance_id = local.kafka_instance_id
  name              = "orders"
  partition         = 3
}

# Kafka SASL credentials are separate from the AutoMQ API Service Account.
resource "automq_kafka_user" "jdbc" {
  environment_id    = local.environment_id
  kafka_instance_id = local.kafka_instance_id
  username          = "jdbc-reader"
  password          = local.kafka_password
}

resource "automq_kafka_acl" "consume_orders" {
  environment_id    = local.environment_id
  kafka_instance_id = local.kafka_instance_id
  resource_type     = "TOPIC"
  resource_name     = automq_kafka_topic.orders.name
  pattern_type      = "LITERAL"
  principal         = "User:${automq_kafka_user.jdbc.username}"
  operation_group   = "CONSUME"
  permission        = "ALLOW"
}

resource "automq_kafka_acl" "connect_group" {
  environment_id    = local.environment_id
  kafka_instance_id = local.kafka_instance_id
  resource_type     = "GROUP"
  resource_name     = "connect-${local.connector_name}"
  pattern_type      = "LITERAL"
  principal         = "User:${automq_kafka_user.jdbc.username}"
  operation_group   = "ALL"
  permission        = "ALLOW"
}

# Register an existing plugin archive compatible with the Connect runtime.
# This resource does not build or upload the archive.
resource "automq_connector_plugin" "jdbc" {
  environment_id  = local.environment_id
  name            = "demo-debezium-jdbc"
  version         = local.plugin_version
  storage_url     = local.plugin_storage_url
  types           = ["SINK"]
  connector_class = "io.debezium.connector.jdbc.JdbcSinkConnector"
}

resource "automq_connect_cluster" "demo" {
  environment_id = local.environment_id
  name           = "azure-connect-demo"
  kafka_cluster = {
    kafka_instance_id = local.kafka_instance_id
  }
  plugins = [{
    name    = automq_connector_plugin.jdbc.name
    version = automq_connector_plugin.jdbc.version
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
      cluster_id      = local.kubernetes_cluster_id
      namespace       = local.connect_namespace
      service_account = local.connect_service_account
      scheduling_spec = yamlencode({
        nodeSelector = {
          "kubernetes.azure.com/agentpool" = local.node_pool_name
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
    "value.converter.schemas.enable" = "true"
  }
}

resource "automq_connector" "orders" {
  environment_id     = local.environment_id
  connect_cluster_id = automq_connect_cluster.demo.id
  name               = local.connector_name
  connector_class    = automq_connector_plugin.jdbc.connector_class
  task_count         = 1
  kafka_cluster = {
    security_protocol = {
      protocol       = "SASL_PLAINTEXT"
      username       = automq_kafka_user.jdbc.username
      password       = local.kafka_password
      sasl_mechanism = "SCRAM-SHA-512"
    }
  }
  connector_config = {
    "topics"                 = automq_kafka_topic.orders.name
    "connection.url"         = local.jdbc_url
    "connection.user"        = local.database_username
    "collection.name.format" = "orders"
    "insert.mode"            = "upsert"
    "primary.key.mode"       = "record_value"
    "primary.key.fields"     = "order_id"
    "schema.evolution"       = "none"
  }
  connector_config_sensitive = {
    "connection.password" = local.database_password
  }
  depends_on = [
    automq_kafka_acl.consume_orders,
    automq_kafka_acl.connect_group,
  ]
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
