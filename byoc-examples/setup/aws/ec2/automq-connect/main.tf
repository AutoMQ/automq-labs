data "http" "console_login" {
  count = local.console_endpoint_valid ? 1 : 0

  url                = "${trimsuffix(local.console_endpoint, "/")}/auth/login"
  request_timeout_ms = 15000
}

resource "terraform_data" "preflight" {
  lifecycle {
    precondition {
      condition     = local.console_state_valid
      error_message = "The Console state must export environment_id, region, ops_bucket_name, console_role_arn, console_security_group_id, console_endpoint, console_initial_access_key, and console_initial_secret_key. Check console_state_path and complete the Console deployment first."
    }

    precondition {
      condition     = local.kafka_state_valid
      error_message = "The Kafka state must export a valid instance_id. Check kafka_state_path and complete the Kafka instance deployment first."
    }

    precondition {
      condition     = !local.console_endpoint_valid || try(data.http.console_login[0].status_code == 200, false)
      error_message = "The Console /auth/login endpoint must return HTTP 200 from the Terraform machine. Check Console readiness, its allowlist, or console_endpoint_override for an open SSM tunnel."
    }

    precondition {
      condition     = data.aws_eks_cluster.target.status == "ACTIVE"
      error_message = "The external EKS cluster must be ACTIVE before creating Connect resources."
    }

    precondition {
      condition     = local.eks_api_security_group_valid
      error_message = "The external EKS cluster must expose a valid primary cluster security group."
    }

    precondition {
      condition     = try(data.aws_eks_cluster.target.vpc_config[0].endpoint_private_access == true, false)
      error_message = "Enable private endpoint access on the external EKS cluster so the Console can reach its API inside the VPC."
    }

    precondition {
      condition     = try(data.aws_security_group.console[0].vpc_id == local.eks_vpc_id, false)
      error_message = "The Console security group and EKS cluster must be in the same VPC for this example's automatic network access."
    }

    precondition {
      condition     = try(split(":", data.aws_security_group.console[0].arn)[4] == data.aws_caller_identity.current.account_id, false)
      error_message = "The Console security group must belong to the current AWS account."
    }

    precondition {
      condition = alltrue([
        for group in data.aws_security_group.workers : group.vpc_id == local.eks_vpc_id
      ])
      error_message = "Every Connect worker security group must belong to the EKS cluster's VPC."
    }

    precondition {
      condition = alltrue([
        for group in data.aws_security_group.workers : try(
          split(":", group.arn)[4] == data.aws_caller_identity.current.account_id,
          false,
        )
      ])
      error_message = "Every Connect worker security group must belong to the current AWS account."
    }

    precondition {
      condition     = try(contains(["API", "API_AND_CONFIG_MAP"], data.aws_eks_cluster.target.access_config[0].authentication_mode), false)
      error_message = "The external EKS cluster must enable access entries with authentication mode API or API_AND_CONFIG_MAP. Update that setting through the EKS owner's infrastructure before applying this example."
    }

    precondition {
      condition     = var.aws_region == local.console_region
      error_message = "aws_region must match the Region exported by the Console state so that EKS and Connect use the environment's Region."
    }

    precondition {
      condition     = try(split(":", data.aws_eks_cluster.target.arn)[4] == data.aws_caller_identity.current.account_id, false)
      error_message = "The EKS cluster and the new Worker IAM Role must belong to the same AWS account."
    }

    precondition {
      condition = try(
        split(":", local.console_role_arn)[4] == data.aws_caller_identity.current.account_id &&
        split(":", local.console_role_arn)[1] == data.aws_partition.current.partition,
        false,
      )
      error_message = "The selected AWS identity and EKS cluster must be in the Console's AWS account and partition. Check aws_profile and console_state_path."
    }

    precondition {
      condition     = contains(data.aws_iam_openid_connect_provider.eks.client_id_list, "sts.amazonaws.com")
      error_message = "The EKS IAM OIDC provider must include sts.amazonaws.com in its client IDs for IRSA. Register or configure that shared provider through the external EKS infrastructure."
    }

    precondition {
      condition = alltrue([
        for arn in var.connect_worker_policy_arns : try(
          split(":", arn)[1] == data.aws_partition.current.partition &&
          contains(["aws", data.aws_caller_identity.current.account_id], split(":", arn)[4]),
          false,
        )
      ])
      error_message = "Worker policy ARNs must belong to this AWS partition and either the current account or AWS managed policies."
    }
  }
}

# Connect workers run on the existing EKS cluster and use the EC2 Kafka instance.
resource "automq_connect_cluster" "demo" {
  depends_on = [
    kubernetes_service_account_v1.connect,
    aws_iam_role_policy.plugin_download,
    aws_iam_role_policy_attachment.connect_worker,
    time_sleep.console_eks_access,
  ]

  environment_id = local.environment_id
  name           = var.connect_cluster_name
  description    = "Connect Cluster with the MySQL Debezium plugin on an existing AWS EKS cluster"
  version        = var.connect_version

  kafka_cluster = {
    kafka_instance_id = local.kafka_instance_id
  }

  plugins = [{
    name    = var.plugin_name
    version = var.plugin_version
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
    iam_role = aws_iam_role.connect_worker.arn
    kubernetes = {
      cluster_id      = data.aws_eks_cluster.target.name
      namespace       = kubernetes_namespace_v1.connect.metadata[0].name
      service_account = kubernetes_service_account_v1.connect.metadata[0].name
      scheduling_spec = var.kubernetes_scheduling_spec
    }
  }

  worker_config = {
    # JsonConverter is the product default. CMP omits default-valued keys on
    # reads, so specifying them causes Provider 0.4.10 state inconsistencies.
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

# Enable MySQL CDC in this same Terraform root after preparing the database.
locals {
  mysql_inputs_valid = (
    try(length(trimspace(var.mysql_hostname)) > 0, false) &&
    try(length(trimspace(var.mysql_user)) > 0, false) &&
    try(length(var.mysql_password) > 0, false)
  )

  # History clients need their own private Kafka bootstrap and security config.
  mysql_bootstrap_candidates = try(distinct([
    for endpoint in data.terraform_remote_state.kafka.outputs.instance_endpoints : trimspace(endpoint.bootstrap_servers)
    if contains(["VPC", "PRIVATE"], upper(endpoint.network_type)) &&
    upper(endpoint.protocol) == "PLAINTEXT" && trimspace(endpoint.bootstrap_servers) != ""
  ]), [])
  mysql_bootstrap_servers = length(local.mysql_bootstrap_candidates) == 1 ? local.mysql_bootstrap_candidates[0] : "missing-vpc-plaintext-endpoint:9092"

  data_topic_name           = "${var.topic_prefix}.${var.mysql_database}.${var.mysql_table}"
  schema_history_topic_name = "schema-history.${var.connector_name}"
}

resource "terraform_data" "mysql_preflight" {
  count = var.create_mysql_connector ? 1 : 0

  depends_on = [terraform_data.preflight]

  lifecycle {
    precondition {
      condition     = local.mysql_inputs_valid
      error_message = "When create_mysql_connector is true, provide mysql_hostname, mysql_user, and mysql_password in terraform.tfvars."
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
    "database.hostname"      = var.mysql_hostname == null ? "" : var.mysql_hostname
    "database.port"          = tostring(var.mysql_port)
    "database.user"          = var.mysql_user == null ? "" : var.mysql_user
    "database.server.id"     = tostring(var.mysql_server_id)
    "database.include.list"  = var.mysql_database
    "table.include.list"     = "${var.mysql_database}\\.${var.mysql_table}"
    "database.ssl.mode"      = var.mysql_ssl_mode
    "topic.prefix"           = var.topic_prefix
    "snapshot.mode"          = "initial"
    "include.schema.changes" = "false"

    # These clients are separate from the producer/consumer overrides that
    # AutoMQ supplies through kafka_cluster.security_protocol above.
    "schema.history.internal.kafka.bootstrap.servers" = local.mysql_bootstrap_servers
    # Let Debezium create schema history through Kafka Admin. CMP's Topic API
    # rejects retention.ms outside 1 hour-60 days, which is too short for history.
    "schema.history.internal.kafka.topic"                = local.schema_history_topic_name
    "schema.history.internal.producer.security.protocol" = "PLAINTEXT"
    "schema.history.internal.consumer.security.protocol" = "PLAINTEXT"
  }

  connector_config_sensitive = {
    "database.password" = var.mysql_password == null ? "" : var.mysql_password
  }

  timeouts = {
    create = "30m"
    update = "30m"
    delete = "10m"
  }
}
