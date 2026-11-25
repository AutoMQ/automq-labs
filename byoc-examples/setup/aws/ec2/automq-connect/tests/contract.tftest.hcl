# All providers and neighboring states are mocked; no cloud/API credentials are used.
# A non-default Region catches accidental hard-coded us-east-1 settings.
mock_provider "automq" {
  mock_resource "automq_connect_cluster" {
    defaults = { id = "connect-cluster-example", state = "RUNNING" }
  }
  mock_resource "automq_connector" {
    defaults = { id = "conn-example", state = "RUNNING", connector_type = "SOURCE", plugin_id = "plugin-example" }
  }
  mock_resource "automq_kafka_topic" {
    defaults = { topic_id = "topic-example" }
  }
}

mock_provider "http" {
  mock_data "http" {
    defaults = { status_code = 200 }
  }
}

mock_provider "aws" {
  mock_data "aws_eks_cluster" {
    defaults = {
      arn           = "arn:aws:eks:eu-west-1:123456789012:cluster/existing-eks-cluster"
      status        = "ACTIVE"
      endpoint      = "https://eks.example.test"
      access_config = [{ authentication_mode = "API_AND_CONFIG_MAP" }]
      vpc_config = [{
        vpc_id                    = "vpc-11111111111111111"
        cluster_security_group_id = "sg-22222222222222222"
        endpoint_private_access   = true
      }]
      certificate_authority = [{ data = "dGVzdC1jYQ==" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE" }] }]
    }
  }
  mock_data "aws_security_group" {
    defaults = {
      arn    = "arn:aws:ec2:eu-west-1:123456789012:security-group/sg-11111111111111111"
      vpc_id = "vpc-11111111111111111"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_iam_openid_connect_provider" {
    defaults = {
      arn            = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE"
      client_id_list = ["sts.amazonaws.com"]
    }
  }
  mock_resource "aws_iam_role" {
    defaults = { name = "mock-connect-worker", arn = "arn:aws:iam::123456789012:role/mock-connect-worker" }
  }
  mock_resource "aws_eks_access_entry" {
    defaults = {
      access_entry_arn = "arn:aws:eks:eu-west-1:123456789012:access-entry/existing-eks-cluster/role/123456789012/example-console/EXAMPLE"
    }
  }
}

mock_provider "kubernetes" {}
mock_provider "time" {}

override_data {
  target = data.terraform_remote_state.console
  values = {
    outputs = {
      environment_id             = "env-example"
      region                     = "eu-west-1"
      ops_bucket_name            = "automq-ops-example"
      console_role_arn           = "arn:aws:iam::123456789012:role/example-console"
      console_security_group_id  = "sg-11111111111111111"
      console_endpoint           = "http://console.example:8080"
      console_initial_access_key = "example-access-key"
      console_initial_secret_key = "example-secret-key"
    }
  }
}

override_data {
  target = data.terraform_remote_state.kafka
  values = {
    outputs = {
      instance_id = "kf-example"
      instance_endpoints = [{
        bootstrap_servers = "kafka.internal.example:9092"
        network_type      = "VPC"
        protocol          = "PLAINTEXT"
      }]
    }
  }
}

variables {
  kubernetes_cluster_id = "existing-eks-cluster"
  plugin_version        = "3.1.2"
}

run "cluster_only_inherits_console_region" {
  command = apply

  # Cluster-only deployment does not need either MySQL inputs or Kafka endpoints.
  override_data {
    target = data.terraform_remote_state.kafka
    values = {
      outputs = { instance_id = "kf-example" }
    }
  }

  assert {
    condition = (
      var.aws_region == null && local.aws_region == "eu-west-1" &&
      automq_connect_cluster.demo.environment_id == "env-example" &&
      automq_connect_cluster.demo.kafka_cluster.kafka_instance_id == "kf-example" &&
      output.connect_cluster_state == "RUNNING" &&
      length(automq_connector.mysql) == 0 && length(automq_kafka_topic.cdc) == 0 &&
      length(terraform_data.mysql_preflight) == 0 &&
      output.mysql_connector_id == null && output.mysql_schema_history_topic == null
    )
    error_message = "The default deployment must inherit the Console Region and create only the Connect Cluster without MySQL credentials or endpoints."
  }

  assert {
    condition = (
      automq_connect_cluster.demo.compute.kubernetes.cluster_id == "existing-eks-cluster" &&
      automq_connect_cluster.demo.compute.kubernetes.namespace == kubernetes_namespace_v1.connect.metadata[0].name &&
      automq_connect_cluster.demo.compute.kubernetes.service_account == kubernetes_service_account_v1.connect.metadata[0].name &&
      automq_connect_cluster.demo.compute.iam_role == aws_iam_role.connect_worker.arn &&
      automq_connect_cluster.demo.capacity.provisioned.worker_count == 1 &&
      automq_connect_cluster.demo.capacity.provisioned.worker_resource_spec == "TIER1" &&
      automq_connect_cluster.demo.plugins[0].name == "mysql-debezium-cdc" &&
      automq_connect_cluster.demo.plugins[0].version == "3.1.2" &&
      length(aws_iam_role_policy_attachment.connect_worker) == 0 &&
      kubernetes_service_account_v1.connect.metadata[0].annotations["eks.amazonaws.com/role-arn"] == aws_iam_role.connect_worker.arn &&
      kubernetes_service_account_v1.connect.automount_service_account_token
    )
    error_message = "One TIER1 worker must use the selected plugin, managed namespace/ServiceAccount, and its IRSA role without optional policies."
  }

  assert {
    condition = (
      automq_connect_cluster.demo.worker_config["key.converter.schemas.enable"] == "false" &&
      automq_connect_cluster.demo.worker_config["value.converter.schemas.enable"] == "false" &&
      !contains(keys(automq_connect_cluster.demo.worker_config), "key.converter") &&
      !contains(keys(automq_connect_cluster.demo.worker_config), "value.converter")
    )
    error_message = "Provider 0.4.10 must rely on default converter classes while retaining the non-default schema settings."
  }

  assert {
    condition = (
      length(jsondecode(aws_iam_role.connect_worker.assume_role_policy).Statement) == 1 &&
      one(jsondecode(aws_iam_role.connect_worker.assume_role_policy).Statement).Action == "sts:AssumeRoleWithWebIdentity" &&
      one(jsondecode(aws_iam_role.connect_worker.assume_role_policy).Statement).Principal.Federated == data.aws_iam_openid_connect_provider.eks.arn &&
      length(keys(one(jsondecode(aws_iam_role.connect_worker.assume_role_policy).Statement).Condition.StringEquals)) == 2 &&
      one(jsondecode(aws_iam_role.connect_worker.assume_role_policy).Statement).Condition.StringEquals["oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE:aud"] == "sts.amazonaws.com" &&
      one(jsondecode(aws_iam_role.connect_worker.assume_role_policy).Statement).Condition.StringEquals["oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE:sub"] == "system:serviceaccount:automq-connect:automq-connect"
    )
    error_message = "IRSA trust must be restricted to the target OIDC provider, STS audience, and exact namespace/ServiceAccount."
  }

  assert {
    condition = (
      aws_iam_role_policy.plugin_download.role == aws_iam_role.connect_worker.name &&
      alltrue([for s in jsondecode(aws_iam_role_policy.plugin_download.policy).Statement : s.Effect == "Allow"]) &&
      toset(flatten([for s in jsondecode(aws_iam_role_policy.plugin_download.policy).Statement : s.Action])) == toset(["s3:GetObject", "s3:ListBucket"]) &&
      one([for s in jsondecode(aws_iam_role_policy.plugin_download.policy).Statement : s if contains(s.Action, "s3:GetObject")]).Resource == "arn:aws:s3:::automq-ops-example/automq/connect-plugins/*" &&
      one([for s in jsondecode(aws_iam_role_policy.plugin_download.policy).Statement : s if contains(s.Action, "s3:ListBucket")]).Resource == "arn:aws:s3:::automq-ops-example" &&
      toset(one([for s in jsondecode(aws_iam_role_policy.plugin_download.policy).Statement : s if contains(s.Action, "s3:ListBucket")]).Condition.StringLike["s3:prefix"]) == toset(["automq/connect-plugins", "automq/connect-plugins/*"])
    )
    error_message = "The Worker Role must only read plugin objects and list their prefix in the Console Ops Bucket."
  }

  assert {
    condition = (
      aws_iam_role_policy.console_eks.role == "example-console" &&
      aws_eks_access_entry.console.principal_arn == "arn:aws:iam::123456789012:role/example-console" &&
      aws_eks_access_entry.console.principal_arn != aws_iam_role.connect_worker.arn &&
      aws_eks_access_entry.console.type == "STANDARD" &&
      aws_eks_access_policy_association.console.cluster_name == data.aws_eks_cluster.target.name &&
      aws_eks_access_policy_association.console.principal_arn == aws_eks_access_entry.console.principal_arn &&
      aws_eks_access_policy_association.console.policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" &&
      aws_eks_access_policy_association.console.access_scope[0].type == "cluster"
    )
    error_message = "EKS administrator access must be granted to the existing Console Role, independently of the Worker Role."
  }

  assert {
    condition = (
      alltrue([for s in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : s.Effect == "Allow"]) &&
      toset(flatten([for s in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : s.Action])) == toset([
        "eks:ListClusters", "eks:DescribeCluster", "eks:ListNodegroups", "eks:DescribeNodegroup",
        "eks:ListAccessEntries", "eks:DescribeAccessEntry", "eks:ListAssociatedAccessPolicies",
      ]) &&
      one([for s in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : s if contains(s.Action, "eks:ListClusters")]).Resource == "*" &&
      one([for s in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : s if contains(s.Action, "eks:ListClusters")]).Condition.StringEquals["aws:RequestedRegion"] == "eu-west-1" &&
      one([for s in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : s if contains(s.Action, "eks:DescribeCluster")]).Resource == "arn:aws:eks:eu-west-1:123456789012:cluster/*" &&
      alltrue([for s in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : s.Resource == data.aws_eks_cluster.target.arn if contains(s.Action, "eks:ListNodegroups") || contains(s.Action, "eks:ListAccessEntries")]) &&
      one([for s in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : s if contains(s.Action, "eks:DescribeNodegroup")]).Resource == "arn:aws:eks:eu-west-1:123456789012:nodegroup/existing-eks-cluster/*/*" &&
      alltrue([for s in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : s.Resource == "arn:aws:eks:eu-west-1:123456789012:access-entry/existing-eks-cluster/*" if contains(s.Action, "eks:DescribeAccessEntry") || contains(s.Action, "eks:ListAssociatedAccessPolicies")])
    )
    error_message = "Console IAM must grant only EKS reads, with discovery in the inherited Region/account and detailed inspection limited to the target cluster."
  }

  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.console_eks_api.security_group_id == "sg-22222222222222222" &&
      aws_vpc_security_group_ingress_rule.console_eks_api.from_port == 443 && aws_vpc_security_group_ingress_rule.console_eks_api.to_port == 443 &&
      toset(keys(aws_vpc_security_group_ingress_rule.console_workers)) == toset(["sg-22222222222222222"]) &&
      alltrue([for id, rule in aws_vpc_security_group_ingress_rule.console_workers : rule.security_group_id == id && rule.from_port == 8083 && rule.to_port == 8083]) &&
      alltrue([for rule in concat([aws_vpc_security_group_ingress_rule.console_eks_api], values(aws_vpc_security_group_ingress_rule.console_workers)) :
        rule.referenced_security_group_id == "sg-11111111111111111" && rule.ip_protocol == "tcp" &&
        rule.cidr_ipv4 == null && rule.cidr_ipv6 == null && rule.prefix_list_id == null
      ]) &&
      time_sleep.console_eks_access.create_duration == "60s" &&
      time_sleep.console_eks_access.triggers["wait_duration"] == "60s"
    )
    error_message = "Only the Console SG may reach EKS TCP 443 and worker TCP 8083; grants must precede the default propagation wait."
  }
}

run "creates_mysql_cdc_with_private_history" {
  command = apply
  variables {
    create_mysql_connector = true
    mysql_hostname         = "mysql.internal.example"
    mysql_user             = "debezium"
    mysql_password         = "example-test-password"
  }

  assert {
    condition = (
      automq_connector.mysql[0].environment_id == "env-example" &&
      automq_connector.mysql[0].connect_cluster_id == automq_connect_cluster.demo.id &&
      automq_connector.mysql[0].connector_class == "io.debezium.connector.mysql.MySqlConnector" &&
      automq_connector.mysql[0].task_count == 1 &&
      automq_connector.mysql[0].kafka_cluster.security_protocol.protocol == "PLAINTEXT" &&
      output.mysql_connector_state == "RUNNING" &&
      automq_connector.mysql[0].connector_config["database.hostname"] == "mysql.internal.example" &&
      automq_connector.mysql[0].connector_config["database.user"] == "debezium" &&
      automq_connector.mysql[0].connector_config["database.port"] == "3306" &&
      automq_connector.mysql[0].connector_config["database.ssl.mode"] == "required" &&
      automq_connector.mysql[0].connector_config["table.include.list"] == "inventory\\.customers" &&
      automq_connector.mysql[0].connector_config["topic.prefix"] == "mysql-cdc" &&
      automq_connector.mysql[0].connector_config["snapshot.mode"] == "initial" &&
      automq_connector.mysql[0].connector_config["include.schema.changes"] == "false"
    )
    error_message = "Enabling CDC must capture the selected MySQL table using one source task, database TLS, and the managed Connect Cluster."
  }

  assert {
    condition = (
      !contains(keys(automq_connector.mysql[0].connector_config), "database.password") &&
      nonsensitive(automq_connector.mysql[0].connector_config_sensitive["database.password"]) == "example-test-password" &&
      !contains(keys(automq_connector.mysql[0].connector_config), "connector.class") &&
      !contains(keys(automq_connector.mysql[0].connector_config), "tasks.max")
    )
    error_message = "The password must only use the sensitive map; AutoMQ supplies connector.class and tasks.max itself."
  }

  assert {
    condition = (
      automq_kafka_topic.cdc[0].kafka_instance_id == "kf-example" &&
      automq_kafka_topic.cdc[0].name == "mysql-cdc.inventory.customers" && automq_kafka_topic.cdc[0].partition == 1 &&
      output.mysql_data_topic == automq_kafka_topic.cdc[0].name &&
      output.mysql_schema_history_topic == "schema-history.mysql-cdc-demo" &&
      automq_connector.mysql[0].connector_config["schema.history.internal.kafka.topic"] == output.mysql_schema_history_topic &&
      automq_connector.mysql[0].connector_config["schema.history.internal.kafka.bootstrap.servers"] == "kafka.internal.example:9092" &&
      automq_connector.mysql[0].connector_config["schema.history.internal.producer.security.protocol"] == "PLAINTEXT" &&
      automq_connector.mysql[0].connector_config["schema.history.internal.consumer.security.protocol"] == "PLAINTEXT"
    )
    error_message = "CDC data must use its managed topic; a distinct history name lets Debezium create long-term history through native Kafka Admin on the private listener."
  }
}

run "custom_settings_and_explicit_region_propagate" {
  command = apply
  variables {
    aws_region                        = "eu-west-1"
    kubernetes_cluster_id             = "custom-eks"
    connect_namespace                 = "custom-connect"
    connect_service_account           = "custom-connect-sa"
    connect_worker_role_name          = "custom-connect-worker"
    connect_worker_policy_arns        = ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess", "arn:aws:iam::123456789012:policy/connect-worker-ops"]
    connect_plugin_s3_prefix          = "custom/connect-plugins"
    connect_worker_security_group_ids = ["sg-33333333", "sg-44444444444444444"]
    console_endpoint_override         = "http://127.0.0.1:18080/"
    console_eks_access_wait_duration  = "0s"
    connect_cluster_name              = "custom-mysql-connect"
    connect_version                   = "test-worker-version"
    worker_count                      = 2
    worker_resource_spec              = "TIER2"
    plugin_name                       = "custom-mysql-debezium"
    plugin_version                    = "test-plugin-version"
    kubernetes_scheduling_spec        = "nodeSelector:\n  workload: connect\n"
    create_mysql_connector            = true
    connector_name                    = "custom-mysql-cdc"
    topic_prefix                      = "custom-cdc"
    mysql_hostname                    = "mysql-staging.internal.example"
    mysql_user                        = "cdcuser"
    mysql_password                    = "alternate-test-password"
    mysql_port                        = 3307
    mysql_server_id                   = 456789
    mysql_database                    = "fulfillment"
    mysql_table                       = "orders"
    mysql_ssl_mode                    = "verify_identity"
  }

  override_data {
    target = data.aws_eks_cluster.target
    values = {
      arn           = "arn:aws:eks:eu-west-1:123456789012:cluster/custom-eks"
      status        = "ACTIVE"
      endpoint      = "https://eks.example.test"
      access_config = [{ authentication_mode = "API" }]
      vpc_config = [{
        vpc_id                    = "vpc-11111111111111111"
        cluster_security_group_id = "sg-22222222222222222"
        endpoint_private_access   = true
      }]
      certificate_authority = [{ data = "dGVzdC1jYQ==" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE" }] }]
    }
  }

  override_data {
    target = data.terraform_remote_state.console
    values = {
      outputs = {
        environment_id             = "env-example"
        region                     = "eu-west-1"
        ops_bucket_name            = "automq-ops-example"
        console_role_arn           = "arn:aws:iam::123456789012:role/team/path/example-console"
        console_security_group_id  = "sg-11111111111111111"
        console_endpoint           = "http://console.example:8080"
        console_initial_access_key = "example-access-key"
        console_initial_secret_key = "example-secret-key"
      }
    }
  }

  assert {
    condition = (
      local.aws_region == "eu-west-1" &&
      data.http.console_login[0].url == "http://127.0.0.1:18080/auth/login" &&
      time_sleep.console_eks_access.create_duration == "0s" &&
      time_sleep.console_eks_access.triggers["wait_duration"] == "0s" &&
      automq_connect_cluster.demo.name == "custom-mysql-connect" &&
      automq_connect_cluster.demo.version == "test-worker-version" &&
      automq_connect_cluster.demo.compute.kubernetes.cluster_id == "custom-eks" &&
      yamldecode(automq_connect_cluster.demo.compute.kubernetes.scheduling_spec).nodeSelector.workload == "connect" &&
      automq_connect_cluster.demo.capacity.provisioned.worker_count == 2 &&
      automq_connect_cluster.demo.capacity.provisioned.worker_resource_spec == "TIER2" &&
      automq_connect_cluster.demo.plugins[0].name == "custom-mysql-debezium" &&
      automq_connect_cluster.demo.plugins[0].version == "test-plugin-version"
    )
    error_message = "An explicit matching Region, SSM URL, disabled wait, and custom worker/plugin settings must remain supported."
  }

  assert {
    condition = (
      aws_iam_role.connect_worker.name == "custom-connect-worker" &&
      kubernetes_service_account_v1.connect.metadata[0].namespace == "custom-connect" &&
      kubernetes_service_account_v1.connect.metadata[0].annotations["eks.amazonaws.com/role-arn"] == aws_iam_role.connect_worker.arn &&
      one(jsondecode(aws_iam_role.connect_worker.assume_role_policy).Statement).Condition.StringEquals["oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE:sub"] == "system:serviceaccount:custom-connect:custom-connect-sa" &&
      toset(keys(aws_iam_role_policy_attachment.connect_worker)) == var.connect_worker_policy_arns &&
      alltrue([for arn, attachment in aws_iam_role_policy_attachment.connect_worker : attachment.policy_arn == arn && attachment.role == aws_iam_role.connect_worker.name]) &&
      one([for s in jsondecode(aws_iam_role_policy.plugin_download.policy).Statement : s if contains(s.Action, "s3:GetObject")]).Resource == "arn:aws:s3:::automq-ops-example/custom/connect-plugins/*" &&
      toset(one([for s in jsondecode(aws_iam_role_policy.plugin_download.policy).Statement : s if contains(s.Action, "s3:ListBucket")]).Condition.StringLike["s3:prefix"]) == toset(["custom/connect-plugins", "custom/connect-plugins/*"])
    )
    error_message = "Custom identities, opt-in policies, and plugin directories must preserve exact IRSA trust and scoped S3 access."
  }

  assert {
    condition = (
      aws_iam_role_policy.console_eks.role == "example-console" &&
      aws_eks_access_entry.console.principal_arn == "arn:aws:iam::123456789012:role/team/path/example-console" &&
      aws_eks_access_policy_association.console.cluster_name == "custom-eks" &&
      one([for s in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : s if contains(s.Action, "eks:DescribeNodegroup")]).Resource == "arn:aws:eks:eu-west-1:123456789012:nodegroup/custom-eks/*/*" &&
      aws_vpc_security_group_ingress_rule.console_eks_api.security_group_id == "sg-22222222222222222" &&
      toset(keys(aws_vpc_security_group_ingress_rule.console_workers)) == var.connect_worker_security_group_ids &&
      alltrue([for id, rule in aws_vpc_security_group_ingress_rule.console_workers :
        rule.security_group_id == id && rule.referenced_security_group_id == "sg-11111111111111111" &&
        rule.ip_protocol == "tcp" && rule.from_port == 8083 && rule.to_port == 8083 &&
        rule.cidr_ipv4 == null && rule.cidr_ipv6 == null && rule.prefix_list_id == null
      ])
    )
    error_message = "Console role paths and target-cluster grants must propagate; custom Worker SGs replace only REST targets, leaving API access on the primary SG."
  }

  assert {
    condition = (
      automq_connector.mysql[0].connector_config["database.hostname"] == "mysql-staging.internal.example" &&
      automq_connector.mysql[0].connector_config["database.user"] == "cdcuser" &&
      automq_connector.mysql[0].connector_config["database.port"] == "3307" &&
      automq_connector.mysql[0].connector_config["database.server.id"] == "456789" &&
      automq_connector.mysql[0].connector_config["database.include.list"] == "fulfillment" &&
      automq_connector.mysql[0].connector_config["table.include.list"] == "fulfillment\\.orders" &&
      automq_connector.mysql[0].connector_config["topic.prefix"] == "custom-cdc" &&
      automq_connector.mysql[0].connector_config["database.ssl.mode"] == "verify_identity" &&
      nonsensitive(automq_connector.mysql[0].connector_config_sensitive["database.password"]) == "alternate-test-password" &&
      automq_kafka_topic.cdc[0].name == "custom-cdc.fulfillment.orders" &&
      automq_connector.mysql[0].connector_config["schema.history.internal.kafka.topic"] == "schema-history.custom-mysql-cdc"
    )
    error_message = "Custom MySQL connection, capture filters, TLS, password, and topic names must propagate together."
  }
}

run "private_listener_selection_filters_and_deduplicates" {
  command = plan

  variables {
    create_mysql_connector = true
    mysql_hostname         = "mysql.internal.example"
    mysql_user             = "debezium"
    mysql_password         = "example-test-password"
  }

  override_data {
    target = data.terraform_remote_state.kafka
    values = {
      outputs = {
        instance_id = "kf-example"
        instance_endpoints = [
          { bootstrap_servers = "kafka.private.example:9092", network_type = "VPC", protocol = "PLAINTEXT" },
          { bootstrap_servers = "kafka.private.example:9092", network_type = "PRIVATE", protocol = "PLAINTEXT" },
          { bootstrap_servers = "kafka.public.example:9092", network_type = "INTERNET", protocol = "PLAINTEXT" },
          { bootstrap_servers = "kafka.auth.example:9094", network_type = "VPC", protocol = "SASL_SSL" },
        ]
      }
    }
  }

  assert {
    condition     = automq_connector.mysql[0].connector_config["schema.history.internal.kafka.bootstrap.servers"] == "kafka.private.example:9092"
    error_message = "Equivalent VPC/PRIVATE listeners must deduplicate, while public and authenticated listeners are excluded."
  }
}

run "enabled_cdc_requires_credentials" {
  command = plan

  variables { create_mysql_connector = true }

  expect_failures = [terraform_data.mysql_preflight[0]]
}

run "ambiguous_private_listeners_are_rejected" {
  command = plan

  variables {
    create_mysql_connector = true
    mysql_hostname         = "mysql.internal.example"
    mysql_user             = "debezium"
    mysql_password         = "example-test-password"
  }

  override_data {
    target = data.terraform_remote_state.kafka
    values = {
      outputs = {
        instance_id = "kf-example"
        instance_endpoints = [
          { bootstrap_servers = "one.internal.example:9092", network_type = "VPC", protocol = "PLAINTEXT" },
          { bootstrap_servers = "two.internal.example:9092", network_type = "PRIVATE", protocol = "PLAINTEXT" },
        ]
      }
    }
  }

  expect_failures = [terraform_data.mysql_preflight[0]]
}

run "public_only_listeners_are_rejected" {
  command = plan

  variables {
    create_mysql_connector = true
    mysql_hostname         = "mysql.internal.example"
    mysql_user             = "debezium"
    mysql_password         = "example-test-password"
  }

  override_data {
    target = data.terraform_remote_state.kafka
    values = {
      outputs = {
        instance_id = "kf-example"
        instance_endpoints = [
          { bootstrap_servers = "kafka.public.example:9092", network_type = "INTERNET", protocol = "PLAINTEXT" },
        ]
      }
    }
  }

  expect_failures = [terraform_data.mysql_preflight[0]]
}

run "invalid_mysql_inputs_are_rejected" {
  command = plan
  variables {
    create_mysql_connector = true
    mysql_hostname         = "REPLACE_WITH_MYSQL_ENDPOINT"
    mysql_user             = "debezium"
    mysql_password         = "example-test-password"
    mysql_port             = 65536
    mysql_server_id        = 0
    connector_name         = "invalid connector name"
    mysql_database         = "invalid.database"
    mysql_table            = "invalid.table"
    topic_prefix           = "invalid topic prefix"
    mysql_ssl_mode         = "unsupported"
  }
  expect_failures = [
    var.mysql_hostname, var.mysql_port, var.mysql_server_id, var.connector_name,
    var.mysql_database, var.mysql_table, var.topic_prefix, var.mysql_ssl_mode,
  ]
}

run "invalid_deployment_inputs_are_rejected" {
  command = plan
  variables {
    kubernetes_cluster_id             = "arn:aws:eks:eu-west-1:123456789012:cluster/existing-eks"
    connect_namespace                 = "kube-system"
    connect_service_account           = "default"
    connect_worker_role_name          = "invalid worker role"
    connect_worker_security_group_ids = ["sg-invalid"]
    connect_plugin_s3_prefix          = "automq/connect-plugins/*"
    console_eks_access_wait_duration  = "forever"
    worker_count                      = 1.5
    worker_resource_spec              = "TIER5"
    plugin_version                    = "REPLACE_WITH_ACTIVE_VERSION"
  }
  expect_failures = [
    var.kubernetes_cluster_id, var.connect_namespace, var.connect_service_account,
    var.connect_worker_role_name, var.connect_worker_security_group_ids,
    var.connect_plugin_s3_prefix, var.console_eks_access_wait_duration,
    var.worker_count, var.worker_resource_spec, var.plugin_version,
  ]
}

run "missing_console_outputs_fail_before_creation" {
  command = plan

  override_data {
    target = data.terraform_remote_state.console
    values = {
      outputs = {}
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "invalid_kafka_instance_fails_before_creation" {
  command = plan

  override_data {
    target = data.terraform_remote_state.kafka
    values = {
      outputs = { instance_id = "invalid-instance" }
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "unready_console_fails_before_creation" {
  command = plan

  override_data {
    target = data.http.console_login[0]
    values = {
      status_code = 503
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "eks_requires_access_entries" {
  command = plan

  override_data {
    target = data.aws_eks_cluster.target
    values = {
      arn           = "arn:aws:eks:eu-west-1:123456789012:cluster/existing-eks-cluster"
      status        = "ACTIVE"
      endpoint      = "https://eks.example.test"
      access_config = [{ authentication_mode = "CONFIG_MAP" }]
      vpc_config = [{
        vpc_id                    = "vpc-11111111111111111"
        cluster_security_group_id = "sg-22222222222222222"
        endpoint_private_access   = true
      }]
      certificate_authority = [{ data = "dGVzdC1jYQ==" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE" }] }]
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "eks_requires_private_api_access" {
  command = plan

  override_data {
    target = data.aws_eks_cluster.target
    values = {
      arn           = "arn:aws:eks:eu-west-1:123456789012:cluster/existing-eks-cluster"
      status        = "ACTIVE"
      endpoint      = "https://eks.example.test"
      access_config = [{ authentication_mode = "API_AND_CONFIG_MAP" }]
      vpc_config = [{
        vpc_id                    = "vpc-11111111111111111"
        cluster_security_group_id = "sg-22222222222222222"
        endpoint_private_access   = false
      }]
      certificate_authority = [{ data = "dGVzdC1jYQ==" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE" }] }]
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "eks_must_be_active" {
  command = plan

  override_data {
    target = data.aws_eks_cluster.target
    values = {
      arn           = "arn:aws:eks:eu-west-1:123456789012:cluster/existing-eks-cluster"
      status        = "CREATING"
      endpoint      = "https://eks.example.test"
      access_config = [{ authentication_mode = "API_AND_CONFIG_MAP" }]
      vpc_config = [{
        vpc_id                    = "vpc-11111111111111111"
        cluster_security_group_id = "sg-22222222222222222"
        endpoint_private_access   = true
      }]
      certificate_authority = [{ data = "dGVzdC1jYQ==" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE" }] }]
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "eks_must_belong_to_current_account" {
  command = plan

  override_data {
    target = data.aws_eks_cluster.target
    values = {
      arn           = "arn:aws:eks:eu-west-1:999999999999:cluster/existing-eks-cluster"
      status        = "ACTIVE"
      endpoint      = "https://eks.example.test"
      access_config = [{ authentication_mode = "API_AND_CONFIG_MAP" }]
      vpc_config = [{
        vpc_id                    = "vpc-11111111111111111"
        cluster_security_group_id = "sg-22222222222222222"
        endpoint_private_access   = true
      }]
      certificate_authority = [{ data = "dGVzdC1jYQ==" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE" }] }]
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "console_role_must_belong_to_current_account" {
  command = plan

  override_data {
    target = data.terraform_remote_state.console
    values = {
      outputs = {
        environment_id             = "env-example"
        region                     = "eu-west-1"
        ops_bucket_name            = "automq-ops-example"
        console_role_arn           = "arn:aws:iam::999999999999:role/foreign-console"
        console_security_group_id  = "sg-11111111111111111"
        console_endpoint           = "http://console.example:8080"
        console_initial_access_key = "example-access-key"
        console_initial_secret_key = "example-secret-key"
      }
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "console_sg_must_share_eks_vpc" {
  command = plan

  override_data {
    target = data.aws_security_group.console[0]
    values = {
      arn    = "arn:aws:ec2:eu-west-1:123456789012:security-group/sg-11111111111111111"
      vpc_id = "vpc-99999999999999999"
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "console_sg_must_belong_to_current_account" {
  command = plan

  override_data {
    target = data.aws_security_group.console[0]
    values = {
      arn    = "arn:aws:ec2:eu-west-1:999999999999:security-group/sg-11111111111111111"
      vpc_id = "vpc-11111111111111111"
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "worker_sg_must_share_eks_vpc" {
  command = plan

  override_data {
    target = data.aws_security_group.workers["sg-22222222222222222"]
    values = {
      arn    = "arn:aws:ec2:eu-west-1:123456789012:security-group/sg-22222222222222222"
      vpc_id = "vpc-99999999999999999"
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "worker_sg_must_belong_to_current_account" {
  command = plan

  override_data {
    target = data.aws_security_group.workers["sg-22222222222222222"]
    values = {
      arn    = "arn:aws:ec2:eu-west-1:999999999999:security-group/sg-22222222222222222"
      vpc_id = "vpc-11111111111111111"
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "worker_policies_reject_foreign_accounts" {
  command = plan

  variables { connect_worker_policy_arns = ["arn:aws:iam::999999999999:policy/foreign-worker"] }

  expect_failures = [terraform_data.preflight]
}

run "worker_policies_reject_foreign_partitions" {
  command = plan

  variables { connect_worker_policy_arns = ["arn:aws-cn:iam::123456789012:policy/foreign-worker"] }

  expect_failures = [terraform_data.preflight]
}

run "oidc_requires_sts_audience" {
  command = plan

  override_data {
    target = data.aws_iam_openid_connect_provider.eks
    values = {
      arn            = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE"
      client_id_list = ["unexpected-audience.example"]
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "explicit_region_must_match_console_state" {
  command = plan

  variables { aws_region = "us-east-1" }

  expect_failures = [terraform_data.preflight]
}
