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

resource "automq_kafka_topic" "orders" {
  environment_id    = "<environment-id>"
  kafka_instance_id = "<kafka-instance-id>"
  name              = "orders"
  partition         = 3
}

# Kafka SASL credentials are separate from the AutoMQ API Service Account.
resource "automq_kafka_user" "jdbc" {
  environment_id    = "<environment-id>"
  kafka_instance_id = "<kafka-instance-id>"
  username          = "jdbc-reader"
  password          = "<kafka-user-password>"
}

resource "automq_kafka_acl" "consume_orders" {
  environment_id    = "<environment-id>"
  kafka_instance_id = "<kafka-instance-id>"
  resource_type     = "TOPIC"
  resource_name     = automq_kafka_topic.orders.name
  pattern_type      = "LITERAL"
  principal         = "User:${automq_kafka_user.jdbc.username}"
  operation_group   = "CONSUME"
  permission        = "ALLOW"
}

resource "automq_kafka_acl" "connect_group" {
  environment_id    = "<environment-id>"
  kafka_instance_id = "<kafka-instance-id>"
  resource_type     = "GROUP"
  resource_name     = "connect-demo-orders-postgres"
  pattern_type      = "LITERAL"
  principal         = "User:${automq_kafka_user.jdbc.username}"
  operation_group   = "ALL"
  permission        = "ALLOW"
}

# Register an existing plugin archive compatible with the Connect runtime.
# This resource does not build or upload the archive.
resource "automq_connector_plugin" "jdbc" {
  environment_id  = "<environment-id>"
  name            = "demo-jdbc"
  version         = "<jdbc-plugin-version>"
  storage_url     = "https://<plugin-host>/kafka-connect-jdbc.zip"
  types           = ["SINK"]
  connector_class = "io.confluent.connect.jdbc.JdbcSinkConnector"
}

resource "automq_connect_cluster" "demo" {
  environment_id = "<environment-id>"
  name           = "azure-connect-demo"
  kafka_cluster = {
    kafka_instance_id = "<kafka-instance-id>"
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
      cluster_id      = "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.ContainerService/managedClusters/<aks-name>"
      namespace       = "<connect-namespace>"
      service_account = "<connect-service-account>"
      scheduling_spec = yamlencode({
        nodeSelector = {
          "kubernetes.azure.com/agentpool" = "<automq-node-pool-name>"
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
  environment_id     = "<environment-id>"
  connect_cluster_id = automq_connect_cluster.demo.id
  name               = "demo-orders-postgres"
  connector_class    = automq_connector_plugin.jdbc.connector_class
  task_count         = 1
  kafka_cluster = {
    security_protocol = {
      protocol       = "SASL_PLAINTEXT"
      username       = automq_kafka_user.jdbc.username
      password       = "<kafka-user-password>"
      sasl_mechanism = "SCRAM-SHA-512"
    }
  }
  connector_config = {
    "topics"            = automq_kafka_topic.orders.name
    "connection.url"    = "jdbc:postgresql://<database-host>:5432/<database-name>?sslmode=require"
    "connection.user"   = "<database-username>"
    "table.name.format" = "orders"
    "insert.mode"       = "upsert"
    "pk.mode"           = "record_value"
    "pk.fields"         = "order_id"
    "auto.create"       = "false"
    "auto.evolve"       = "false"
  }
  connector_config_sensitive = {
    "connection.password" = "<database-password>"
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
