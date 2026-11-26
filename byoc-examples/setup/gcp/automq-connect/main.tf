data "http" "console_login" {
  count = local.console_endpoint_valid ? 1 : 0

  url                = "${trimsuffix(local.console_endpoint, "/")}/auth/login"
  request_timeout_ms = 15000
}

resource "terraform_data" "preflight" {
  lifecycle {
    precondition {
      condition     = local.console_state_valid
      error_message = "The Console state must export automq_environment_id, project_id, region, network_id, console_service_account_email, console_endpoint, console_initial_access_key, and console_initial_secret_key. Complete the GCP Console deployment first."
    }

    precondition {
      condition     = local.kafka_state_valid
      error_message = "The Kafka state must export a valid instance_id. Complete the AutoMQ Instance deployment first."
    }

    precondition {
      condition     = trimspace(local.ops_bucket_name) != ""
      error_message = "The Console state must export ops_bucket_name. Run terraform apply -refresh-only in the Console Terraform directory to publish this output before creating Connect."
    }

    precondition {
      condition     = !local.console_endpoint_valid || try(data.http.console_login[0].status_code == 200, false)
      error_message = "The Console /auth/login endpoint must return HTTP 200 from the Terraform machine. Check readiness, its ingress allowlist, or console_endpoint_override."
    }

    precondition {
      condition     = local.gke_project_id == local.console_project
      error_message = "The external GKE cluster must be in the Console's GCP project for this example."
    }

    precondition {
      condition     = local.gke_location == local.console_region || startswith(local.gke_location, "${local.console_region}-")
      error_message = "The external GKE location must be in the Console's Region."
    }

    precondition {
      condition = (
        local.gke_network_id == local.console_network &&
        startswith(local.gke_network_id, "projects/${local.gke_project_id}/global/networks/")
      )
      error_message = "The Console and GKE cluster must use the same VPC in their service project. Cross-project Shared VPC networking is outside this example."
    }

    precondition {
      condition     = local.workload_identity_pool == "${local.gke_project_id}.svc.id.goog"
      error_message = "Enable Workload Identity Federation on the external GKE cluster before applying this example."
    }

    precondition {
      condition     = local.connect_node_pool != null
      error_message = "connect_node_pool_name must identify an existing node pool in the external GKE cluster. This example does not create a node pool."
    }

    precondition {
      condition     = try(local.connect_node_pool.node_config[0].workload_metadata_config[0].mode == "GKE_METADATA", false)
      error_message = "The selected Connect node pool must use GKE_METADATA so workers receive their Workload Identity credentials."
    }

    precondition {
      condition     = length(local.unmatched_node_taints) == 0
      error_message = "The selected node pool has NoSchedule or NoExecute taints without matching connect_tolerations. Select another pool or provide the required tolerations."
    }
  }
}

resource "automq_connect_cluster" "demo" {
  depends_on = [time_sleep.workload_identity, google_compute_firewall.console_to_workers]

  environment_id = local.environment_id
  name           = var.connect_cluster_name
  description    = "Debezium MySQL demo on an existing GKE cluster"
  version        = var.connect_version

  kafka_cluster = {
    kafka_instance_id = local.kafka_instance_id
  }

  # Fixed system plugin for this customer demo; Console must report it ACTIVE.
  plugins = [{
    name    = "debezium-mysql"
    version = "3.1.2"
  }]

  capacity = {
    type = "provisioned"
    provisioned = {
      worker_count         = var.worker_count
      worker_resource_spec = var.worker_resource_spec
    }
  }

  compute = {
    type     = "k8s"
    iam_role = google_service_account.connect_worker.name
    kubernetes = {
      cluster_id      = var.kubernetes_cluster_id
      namespace       = kubernetes_namespace_v1.connect.metadata[0].name
      service_account = kubernetes_service_account_v1.connect.metadata[0].name
      scheduling_spec = local.connect_scheduling_spec
    }
  }

  worker_config = {
    # Rely on default converter classes: CMP omits default-valued keys on reads.
    "key.converter.schemas.enable"   = "false"
    "value.converter.schemas.enable" = "false"
  }

  tags = var.tags

  timeouts = {
    create = "30m"
    update = "30m"
    delete = "20m"
  }
}

locals {
  mysql_inputs_valid = (
    try(length(trimspace(var.mysql_hostname)) > 0, false) &&
    try(length(trimspace(var.mysql_user)) > 0, false) &&
    try(length(var.mysql_password) > 0, false)
  )

  # Debezium's schema history clients need their own Kafka connection settings.
  mysql_bootstrap_candidates = try(distinct([
    for endpoint in data.terraform_remote_state.kafka.outputs.instance_endpoints : trimspace(endpoint.bootstrap_servers)
    if contains(["VPC", "PRIVATE"], upper(endpoint.network_type)) &&
    upper(endpoint.protocol) == "PLAINTEXT" && trimspace(endpoint.bootstrap_servers) != ""
  ]), [])
  mysql_bootstrap_servers = try(one(local.mysql_bootstrap_candidates), null)

  data_topic_name           = "${var.topic_prefix}.${var.mysql_database}.${var.mysql_table}"
  schema_history_topic_name = "schema-history.${var.connector_name}"
}

resource "terraform_data" "mysql_preflight" {
  count = var.create_mysql_connector ? 1 : 0

  depends_on = [terraform_data.preflight]

  lifecycle {
    precondition {
      condition     = local.mysql_inputs_valid
      error_message = "When create_mysql_connector is true, provide mysql_hostname, mysql_user, and mysql_password."
    }

    precondition {
      condition     = length(local.mysql_bootstrap_candidates) == 1
      error_message = "MySQL CDC requires exactly one distinct VPC or PRIVATE PLAINTEXT bootstrap_servers value in the Kafka state. This example does not configure SASL/SSL Kafka clients."
    }
  }
}

resource "automq_kafka_topic" "cdc" {
  count = var.create_mysql_connector ? 1 : 0

  depends_on = [terraform_data.mysql_preflight, automq_connect_cluster.demo]

  environment_id    = local.environment_id
  kafka_instance_id = local.kafka_instance_id
  name              = local.data_topic_name
  partition         = 1
}

resource "automq_connector" "mysql" {
  count = var.create_mysql_connector ? 1 : 0

  depends_on = [automq_kafka_topic.cdc]

  environment_id     = local.environment_id
  connect_cluster_id = automq_connect_cluster.demo.id
  name               = var.connector_name
  description        = "MySQL Debezium CDC for ${var.mysql_database}.${var.mysql_table}"
  connector_class    = "io.debezium.connector.mysql.MySqlConnector"
  task_count         = 1

  kafka_cluster = {
    security_protocol = {
      protocol = "PLAINTEXT"
    }
  }

  connector_config = {
    "database.hostname"      = var.mysql_hostname
    "database.port"          = tostring(var.mysql_port)
    "database.user"          = var.mysql_user
    "database.server.id"     = tostring(var.mysql_server_id)
    "database.include.list"  = var.mysql_database
    "table.include.list"     = "${var.mysql_database}\\.${var.mysql_table}"
    "database.ssl.mode"      = var.mysql_ssl_mode
    "topic.prefix"           = var.topic_prefix
    "snapshot.mode"          = "initial"
    "include.schema.changes" = "false"

    # CMP's Topic API cannot express the indefinite schema-history retention.
    # Debezium creates this internal topic through Kafka Admin instead.
    "schema.history.internal.kafka.bootstrap.servers"    = local.mysql_bootstrap_servers
    "schema.history.internal.kafka.topic"                = local.schema_history_topic_name
    "schema.history.internal.producer.security.protocol" = "PLAINTEXT"
    "schema.history.internal.consumer.security.protocol" = "PLAINTEXT"
  }

  connector_config_sensitive = {
    "database.password" = var.mysql_password
  }

  timeouts = {
    create = "30m"
    update = "30m"
    delete = "10m"
  }
}
