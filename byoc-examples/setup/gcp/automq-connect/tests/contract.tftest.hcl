# All cloud providers and adjacent Terraform states are mocked.
# A non-default region and project detect accidental environment hard-coding.
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

mock_provider "google" {
  mock_data "google_container_cluster" {
    defaults = {
      id       = "projects/example-project/locations/europe-west1/clusters/existing-gke"
      endpoint = "127.0.0.1"
      network  = "projects/example-project/global/networks/existing-vpc"
      master_auth = [{
        cluster_ca_certificate = "dGVzdC1jYQ=="
      }]
      workload_identity_config = [{ workload_pool = "example-project.svc.id.goog" }]
      node_pool = [{
        name = "default-pool"
        node_config = [{
          service_account          = "gke-nodes@example-project.iam.gserviceaccount.com"
          workload_metadata_config = [{ mode = "GKE_METADATA" }]
          taint                    = []
        }]
      }]
    }
  }

  mock_data "google_project" {
    defaults = {
      project_id = "example-project"
      number     = "123456789012"
    }
  }

  mock_resource "google_service_account" {
    defaults = {
      name  = "projects/example-project/serviceAccounts/mock-connect-worker@example-project.iam.gserviceaccount.com"
      email = "mock-connect-worker@example-project.iam.gserviceaccount.com"
    }
  }
}

mock_provider "kubernetes" {}
mock_provider "time" {}

override_data {
  target = data.terraform_remote_state.console
  values = {
    outputs = {
      automq_environment_id         = "env-example"
      project_id                    = "example-project"
      region                        = "europe-west1"
      network_id                    = "projects/example-project/global/networks/existing-vpc"
      console_service_account_email = "console@example-project.iam.gserviceaccount.com"
      console_endpoint              = "http://console.example:8080"
      console_initial_access_key    = "example-access-key"
      console_initial_secret_key    = "example-secret-key"
      ops_bucket_name               = "automq-ops-example"
    }
  }
}

override_data {
  target = data.terraform_remote_state.kafka
  values = {
    outputs = { instance_id = "kf-example" }
  }
}

variables {
  kubernetes_cluster_id = "projects/example-project/locations/europe-west1/clusters/existing-gke"
  # Keep cluster-only tests independent of a local demo's optional CDC settings.
  create_mysql_connector = false
}

run "creates_fixed_mysql_demo_on_external_gke" {
  command = apply

  assert {
    condition = (
      !var.create_mysql_connector &&
      length(terraform_data.mysql_preflight) == 0 &&
      length(automq_connector.mysql) == 0 &&
      length(automq_kafka_topic.cdc) == 0 &&
      output.mysql_connector_id == null &&
      output.mysql_connector_state == null &&
      output.mysql_data_topic == null &&
      output.mysql_schema_history_topic == null
    )
    error_message = "Cluster-only deployment must not require Kafka endpoints or MySQL inputs, and must not create a connector or topic."
  }

  assert {
    condition = (
      local.gke_project_id == "example-project" &&
      local.gke_location == "europe-west1" &&
      local.gke_cluster_name == "existing-gke" &&
      automq_connect_cluster.demo.environment_id == "env-example" &&
      automq_connect_cluster.demo.kafka_cluster.kafka_instance_id == "kf-example" &&
      automq_connect_cluster.demo.compute.kubernetes.cluster_id == var.kubernetes_cluster_id &&
      automq_connect_cluster.demo.capacity.type == "provisioned" &&
      automq_connect_cluster.demo.capacity.provisioned.worker_resource_spec == "TIER1" &&
      automq_connect_cluster.demo.capacity.provisioned.worker_count == 1 &&
      automq_connect_cluster.demo.state == "RUNNING"
    )
    error_message = "The demo must reuse the externally supplied GKE and existing Kafka instance with one fixed TIER1 worker."
  }

  assert {
    condition = (
      length(automq_connect_cluster.demo.plugins) == 1 &&
      automq_connect_cluster.demo.plugins[0].name == "debezium-mysql" &&
      automq_connect_cluster.demo.plugins[0].version == "3.1.2" &&
      automq_connect_cluster.demo.worker_config["key.converter.schemas.enable"] == "false" &&
      automq_connect_cluster.demo.worker_config["value.converter.schemas.enable"] == "false" &&
      !contains(keys(automq_connect_cluster.demo.worker_config), "key.converter") &&
      !contains(keys(automq_connect_cluster.demo.worker_config), "value.converter")
    )
    error_message = "The customer demo must install only the fixed Debezium MySQL 3.1.2 plugin and retain Provider-compatible converter settings."
  }

  assert {
    condition = (
      automq_connect_cluster.demo.compute.iam_role == google_service_account.connect_worker.name &&
      startswith(automq_connect_cluster.demo.compute.iam_role, "projects/example-project/serviceAccounts/") &&
      automq_connect_cluster.demo.compute.kubernetes.namespace == kubernetes_namespace_v1.connect.metadata[0].name &&
      automq_connect_cluster.demo.compute.kubernetes.service_account == kubernetes_service_account_v1.connect.metadata[0].name &&
      kubernetes_service_account_v1.connect.metadata[0].namespace == kubernetes_namespace_v1.connect.metadata[0].name &&
      kubernetes_service_account_v1.connect.metadata[0].annotations["iam.gke.io/gcp-service-account"] == google_service_account.connect_worker.email &&
      google_service_account_iam_member.workload_identity.service_account_id == google_service_account.connect_worker.name &&
      google_service_account_iam_member.workload_identity.role == "roles/iam.workloadIdentityUser" &&
      google_service_account_iam_member.workload_identity.member == "serviceAccount:example-project.svc.id.goog[automq-connect/automq-connect]"
    )
    error_message = "Workload Identity must connect the exact namespace/KSA to the new GSA, and the API must receive the full GSA resource name."
  }

  assert {
    condition = (
      google_storage_bucket_iam_member.ops.bucket == "automq-ops-example" &&
      google_storage_bucket_iam_member.ops.role == "roles/storage.objectUser" &&
      google_storage_bucket_iam_member.ops.member == format("serviceAccount:%s", google_service_account.connect_worker.email) &&
      google_project_service.iam_credentials.project == "example-project" &&
      google_project_service.iam_credentials.service == "iamcredentials.googleapis.com"
    )
    error_message = "Worker telemetry access must be scoped to the existing Ops Bucket, with the service account credentials API enabled."
  }

  assert {
    condition = (
      yamldecode(automq_connect_cluster.demo.compute.kubernetes.scheduling_spec).nodeSelector["cloud.google.com/gke-nodepool"] == "default-pool" &&
      !contains(keys(yamldecode(automq_connect_cluster.demo.compute.kubernetes.scheduling_spec)), "tolerations") &&
      google_compute_firewall.console_to_workers.network == "projects/example-project/global/networks/existing-vpc" &&
      google_compute_firewall.console_to_workers.direction == "INGRESS" &&
      toset(google_compute_firewall.console_to_workers.source_service_accounts) == toset(["console@example-project.iam.gserviceaccount.com"]) &&
      toset(google_compute_firewall.console_to_workers.target_service_accounts) == toset(["gke-nodes@example-project.iam.gserviceaccount.com"]) &&
      one(google_compute_firewall.console_to_workers.allow).protocol == "tcp" &&
      toset(one(google_compute_firewall.console_to_workers.allow).ports) == toset(["8083", "9090"]) &&
      length(coalesce(google_compute_firewall.console_to_workers.source_ranges, [])) == 0
    )
    error_message = "Workers must select the external node pool, omit empty tolerations rejected by Console 8.4.13, and permit only Console-identity ingress on REST/metrics ports."
  }
}

run "custom_pool_and_identity_keep_plugin_fixed" {
  command = apply

  variables {
    connect_node_pool_name    = "cdc-pool"
    connect_cluster_name      = "custom-mysql-demo"
    connect_namespace         = "mysql-connect"
    connect_service_account   = "mysql-worker"
    worker_service_account_id = "mysql-connect-worker"
    connect_version           = "test-worker-version"
    worker_count              = 2
    worker_resource_spec      = "TIER2"
    console_endpoint_override = "http://127.0.0.1:18080/"
    connect_tolerations = [{
      key      = "dedicated"
      operator = "Equal"
      value    = "cdc"
      effect   = "NoSchedule"
    }]
    tags = { purpose = "customer-demo" }
  }

  override_data {
    target = data.google_container_cluster.target
    values = {
      id       = "projects/example-project/locations/europe-west1/clusters/existing-gke"
      endpoint = "127.0.0.1"
      network  = "projects/example-project/global/networks/existing-vpc"
      master_auth = [{
        cluster_ca_certificate = "dGVzdC1jYQ=="
      }]
      workload_identity_config = [{ workload_pool = "example-project.svc.id.goog" }]
      node_pool = [{
        name = "cdc-pool"
        node_config = [{
          service_account          = "custom-nodes@example-project.iam.gserviceaccount.com"
          workload_metadata_config = [{ mode = "GKE_METADATA" }]
          taint                    = [{ key = "dedicated", value = "cdc", effect = "NO_SCHEDULE" }]
        }]
      }]
    }
  }

  assert {
    condition = (
      automq_connect_cluster.demo.name == "custom-mysql-demo" &&
      automq_connect_cluster.demo.version == "test-worker-version" &&
      automq_connect_cluster.demo.capacity.provisioned.worker_count == 2 &&
      automq_connect_cluster.demo.capacity.provisioned.worker_resource_spec == "TIER2" &&
      automq_connect_cluster.demo.tags["purpose"] == "customer-demo" &&
      local.console_endpoint == "http://127.0.0.1:18080" &&
      automq_connect_cluster.demo.plugins[0].name == "debezium-mysql" &&
      automq_connect_cluster.demo.plugins[0].version == "3.1.2"
    )
    error_message = "Custom worker capacity, version, and endpoint must propagate without parameterizing the fixed demo plugin."
  }

  assert {
    condition = (
      google_service_account.connect_worker.account_id == "mysql-connect-worker" &&
      kubernetes_namespace_v1.connect.metadata[0].name == "mysql-connect" &&
      kubernetes_service_account_v1.connect.metadata[0].name == "mysql-worker" &&
      google_service_account_iam_member.workload_identity.member == "serviceAccount:example-project.svc.id.goog[mysql-connect/mysql-worker]" &&
      yamldecode(local.connect_scheduling_spec).nodeSelector["cloud.google.com/gke-nodepool"] == "cdc-pool" &&
      yamldecode(local.connect_scheduling_spec).tolerations[0].key == "dedicated" &&
      yamldecode(local.connect_scheduling_spec).tolerations[0].value == "cdc" &&
      yamldecode(local.connect_scheduling_spec).tolerations[0].effect == "NoSchedule" &&
      toset(google_compute_firewall.console_to_workers.target_service_accounts) == toset(["custom-nodes@example-project.iam.gserviceaccount.com"])
    )
    error_message = "Custom namespace, KSA, GSA, pool selection and taint toleration must stay aligned with the selected pool's VM identity."
  }
}

run "default_compute_identity_uses_project_number" {
  command = apply

  override_data {
    target = data.google_container_cluster.target
    values = {
      id       = "projects/example-project/locations/europe-west1/clusters/existing-gke"
      endpoint = "127.0.0.1"
      network  = "projects/example-project/global/networks/existing-vpc"
      master_auth = [{
        cluster_ca_certificate = "dGVzdC1jYQ=="
      }]
      workload_identity_config = [{ workload_pool = "example-project.svc.id.goog" }]
      node_pool = [{
        name = "default-pool"
        node_config = [{
          service_account          = "default"
          workload_metadata_config = [{ mode = "GKE_METADATA" }]
          taint                    = []
        }]
      }]
    }
  }

  assert {
    condition     = toset(google_compute_firewall.console_to_workers.target_service_accounts) == toset(["123456789012-compute@developer.gserviceaccount.com"])
    error_message = "The default node VM identity must resolve from the GKE project number, not the Worker GSA or a hard-coded email."
  }
}

run "missing_ops_bucket_output_is_rejected" {
  command = plan

  override_data {
    target = data.terraform_remote_state.console
    values = {
      outputs = {
        automq_environment_id         = "env-example"
        project_id                    = "example-project"
        region                        = "europe-west1"
        network_id                    = "projects/example-project/global/networks/existing-vpc"
        console_service_account_email = "console@example-project.iam.gserviceaccount.com"
        console_endpoint              = "http://console.example:8080"
        console_initial_access_key    = "example-access-key"
        console_initial_secret_key    = "example-secret-key"
      }
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "cross_project_gke_is_rejected" {
  command = plan

  variables {
    kubernetes_cluster_id = "projects/foreign-project/locations/europe-west1/clusters/existing-gke"
  }

  expect_failures = [terraform_data.preflight]
}

run "disabled_workload_identity_is_rejected" {
  command = plan

  override_data {
    target = data.google_container_cluster.target
    values = {
      id       = "projects/example-project/locations/europe-west1/clusters/existing-gke"
      endpoint = "127.0.0.1"
      network  = "projects/example-project/global/networks/existing-vpc"
      master_auth = [{
        cluster_ca_certificate = "dGVzdC1jYQ=="
      }]
      workload_identity_config = []
      node_pool = [{
        name = "default-pool"
        node_config = [{
          service_account          = "gke-nodes@example-project.iam.gserviceaccount.com"
          workload_metadata_config = [{ mode = "GKE_METADATA" }]
          taint                    = []
        }]
      }]
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "missing_node_pool_is_rejected" {
  command = plan

  override_data {
    target = data.google_container_cluster.target
    values = {
      id       = "projects/example-project/locations/europe-west1/clusters/existing-gke"
      endpoint = "127.0.0.1"
      network  = "projects/example-project/global/networks/existing-vpc"
      master_auth = [{
        cluster_ca_certificate = "dGVzdC1jYQ=="
      }]
      workload_identity_config = [{ workload_pool = "example-project.svc.id.goog" }]
      node_pool = [{
        name = "other-pool"
        node_config = [{
          service_account          = "gke-nodes@example-project.iam.gserviceaccount.com"
          workload_metadata_config = [{ mode = "GKE_METADATA" }]
          taint                    = []
        }]
      }]
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "node_vm_metadata_mode_is_rejected" {
  command = plan

  override_data {
    target = data.google_container_cluster.target
    values = {
      id       = "projects/example-project/locations/europe-west1/clusters/existing-gke"
      endpoint = "127.0.0.1"
      network  = "projects/example-project/global/networks/existing-vpc"
      master_auth = [{
        cluster_ca_certificate = "dGVzdC1jYQ=="
      }]
      workload_identity_config = [{ workload_pool = "example-project.svc.id.goog" }]
      node_pool = [{
        name = "default-pool"
        node_config = [{
          service_account          = "gke-nodes@example-project.iam.gserviceaccount.com"
          workload_metadata_config = [{ mode = "GCE_METADATA" }]
          taint                    = []
        }]
      }]
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "different_console_vpc_is_rejected" {
  command = plan

  override_data {
    target = data.google_container_cluster.target
    values = {
      id       = "projects/example-project/locations/europe-west1/clusters/existing-gke"
      endpoint = "127.0.0.1"
      network  = "projects/example-project/global/networks/another-vpc"
      master_auth = [{
        cluster_ca_certificate = "dGVzdC1jYQ=="
      }]
      workload_identity_config = [{ workload_pool = "example-project.svc.id.goog" }]
      node_pool = [{
        name = "default-pool"
        node_config = [{
          service_account          = "gke-nodes@example-project.iam.gserviceaccount.com"
          workload_metadata_config = [{ mode = "GKE_METADATA" }]
          taint                    = []
        }]
      }]
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "unmatched_node_taint_is_rejected" {
  command = plan

  override_data {
    target = data.google_container_cluster.target
    values = {
      id       = "projects/example-project/locations/europe-west1/clusters/existing-gke"
      endpoint = "127.0.0.1"
      network  = "projects/example-project/global/networks/existing-vpc"
      master_auth = [{
        cluster_ca_certificate = "dGVzdC1jYQ=="
      }]
      workload_identity_config = [{ workload_pool = "example-project.svc.id.goog" }]
      node_pool = [{
        name = "default-pool"
        node_config = [{
          service_account          = "gke-nodes@example-project.iam.gserviceaccount.com"
          workload_metadata_config = [{ mode = "GKE_METADATA" }]
          taint                    = [{ key = "dedicated", value = "cdc", effect = "NO_SCHEDULE" }]
        }]
      }]
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "missing_console_outputs_are_rejected" {
  command = plan

  override_data {
    target = data.terraform_remote_state.console
    values = { outputs = {} }
  }

  expect_failures = [terraform_data.preflight]
}

run "missing_kafka_instance_is_rejected" {
  command = plan

  override_data {
    target = data.terraform_remote_state.kafka
    values = { outputs = {} }
  }

  expect_failures = [terraform_data.preflight]
}

run "invalid_cluster_id_is_rejected" {
  command = plan

  variables { kubernetes_cluster_id = "existing-gke" }

  expect_failures = [var.kubernetes_cluster_id]
}

run "invalid_demo_parameters_are_rejected" {
  command = plan

  variables {
    connect_cluster_name      = "invalid name"
    connect_namespace         = "kube-system"
    connect_service_account   = "default"
    worker_service_account_id = "INVALID_ID"
    connect_node_pool_name    = ""
    worker_count              = 1.5
    worker_resource_spec      = "TIER5"
    connect_version           = ""
  }

  expect_failures = [
    var.connect_cluster_name, var.connect_namespace, var.connect_service_account,
    var.worker_service_account_id, var.connect_node_pool_name,
    var.worker_count, var.worker_resource_spec, var.connect_version,
  ]
}

run "enabled_mysql_cdc_uses_private_kafka_and_sensitive_password" {
  command = apply

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
        instance_endpoints = [{
          bootstrap_servers = "kafka.internal.example:9092"
          network_type      = "VPC"
          protocol          = "PLAINTEXT"
        }]
      }
    }
  }

  assert {
    condition = (
      length(automq_connector.mysql) == 1 &&
      length(automq_kafka_topic.cdc) == 1 &&
      automq_connector.mysql[0].environment_id == "env-example" &&
      automq_connector.mysql[0].connect_cluster_id == automq_connect_cluster.demo.id &&
      automq_connector.mysql[0].connector_class == "io.debezium.connector.mysql.MySqlConnector" &&
      automq_connector.mysql[0].task_count == 1 &&
      automq_connector.mysql[0].kafka_cluster.security_protocol.protocol == "PLAINTEXT" &&
      automq_kafka_topic.cdc[0].kafka_instance_id == "kf-example" &&
      automq_kafka_topic.cdc[0].name == "mysql-cdc.inventory.customers" &&
      automq_kafka_topic.cdc[0].partition == 1 &&
      output.mysql_connector_id == automq_connector.mysql[0].id &&
      output.mysql_connector_state == "RUNNING" &&
      output.mysql_data_topic == automq_kafka_topic.cdc[0].name
    )
    error_message = "Enabling CDC must create one MySQL source task and one CDC data topic on the existing Kafka instance and Connect Cluster."
  }

  assert {
    condition = (
      automq_connector.mysql[0].connector_config["database.hostname"] == "mysql.internal.example" &&
      automq_connector.mysql[0].connector_config["database.port"] == "3306" &&
      automq_connector.mysql[0].connector_config["database.user"] == "debezium" &&
      automq_connector.mysql[0].connector_config["database.server.id"] == "184054" &&
      automq_connector.mysql[0].connector_config["database.include.list"] == "inventory" &&
      automq_connector.mysql[0].connector_config["table.include.list"] == "inventory\\.customers" &&
      automq_connector.mysql[0].connector_config["database.ssl.mode"] == "required" &&
      automq_connector.mysql[0].connector_config["topic.prefix"] == "mysql-cdc" &&
      automq_connector.mysql[0].connector_config["snapshot.mode"] == "initial" &&
      automq_connector.mysql[0].connector_config["include.schema.changes"] == "false"
    )
    error_message = "MySQL connection, capture filters, escaped table regex, TLS, topic namespace, and initial snapshot settings must match the demo inputs."
  }

  assert {
    condition = (
      !contains(keys(automq_connector.mysql[0].connector_config), "database.password") &&
      nonsensitive(automq_connector.mysql[0].connector_config_sensitive["database.password"]) == "example-test-password" &&
      !contains(keys(automq_connector.mysql[0].connector_config), "connector.class") &&
      !contains(keys(automq_connector.mysql[0].connector_config), "tasks.max")
    )
    error_message = "The database password must only use the sensitive map; connector class and task count belong to the provider's dedicated attributes."
  }

  assert {
    condition = (
      output.mysql_schema_history_topic == "schema-history.mysql-cdc-demo" &&
      output.mysql_schema_history_topic != output.mysql_data_topic &&
      automq_connector.mysql[0].connector_config["schema.history.internal.kafka.topic"] == output.mysql_schema_history_topic &&
      automq_connector.mysql[0].connector_config["schema.history.internal.kafka.bootstrap.servers"] == "kafka.internal.example:9092" &&
      automq_connector.mysql[0].connector_config["schema.history.internal.producer.security.protocol"] == "PLAINTEXT" &&
      automq_connector.mysql[0].connector_config["schema.history.internal.consumer.security.protocol"] == "PLAINTEXT"
    )
    error_message = "Debezium history must use its distinct, non-managed history topic and the unique private plaintext listener."
  }
}

run "mysql_cdc_custom_inputs_propagate_together" {
  command = apply

  variables {
    create_mysql_connector = true
    connector_name         = "custom-mysql-cdc"
    mysql_hostname         = "mysql-staging.internal.example"
    mysql_port             = 3307
    mysql_user             = "cdcuser"
    mysql_password         = "alternate-test-password"
    mysql_database         = "fulfillment"
    mysql_table            = "orders"
    mysql_server_id        = 456789
    mysql_ssl_mode         = "verify_identity"
    topic_prefix           = "custom-cdc"
  }

  override_data {
    target = data.terraform_remote_state.kafka
    values = {
      outputs = {
        instance_id = "kf-example"
        instance_endpoints = [{
          bootstrap_servers = "kafka.internal.example:9092"
          network_type      = "PRIVATE"
          protocol          = "PLAINTEXT"
        }]
      }
    }
  }

  assert {
    condition = (
      automq_connector.mysql[0].name == "custom-mysql-cdc" &&
      automq_connector.mysql[0].connector_config["database.hostname"] == "mysql-staging.internal.example" &&
      automq_connector.mysql[0].connector_config["database.port"] == "3307" &&
      automq_connector.mysql[0].connector_config["database.user"] == "cdcuser" &&
      nonsensitive(automq_connector.mysql[0].connector_config_sensitive["database.password"]) == "alternate-test-password" &&
      automq_connector.mysql[0].connector_config["database.server.id"] == "456789" &&
      automq_connector.mysql[0].connector_config["database.include.list"] == "fulfillment" &&
      automq_connector.mysql[0].connector_config["table.include.list"] == "fulfillment\\.orders" &&
      automq_connector.mysql[0].connector_config["database.ssl.mode"] == "verify_identity" &&
      automq_connector.mysql[0].connector_config["topic.prefix"] == "custom-cdc" &&
      automq_kafka_topic.cdc[0].name == "custom-cdc.fulfillment.orders" &&
      output.mysql_schema_history_topic == "schema-history.custom-mysql-cdc"
    )
    error_message = "Customized MySQL connection, credentials, capture names, TLS, server ID, and schema-history name must stay aligned."
  }
}

run "mysql_private_listeners_filter_and_deduplicate" {
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
          { bootstrap_servers = "kafka.internal.example:9092", network_type = "VPC", protocol = "PLAINTEXT" },
          { bootstrap_servers = "kafka.internal.example:9092", network_type = "PRIVATE", protocol = "PLAINTEXT" },
          { bootstrap_servers = "kafka.public.example:9092", network_type = "INTERNET", protocol = "PLAINTEXT" },
          { bootstrap_servers = "kafka.auth.example:9094", network_type = "VPC", protocol = "SASL_SSL" },
        ]
      }
    }
  }

  assert {
    condition = (
      length(local.mysql_bootstrap_candidates) == 1 &&
      automq_connector.mysql[0].connector_config["schema.history.internal.kafka.bootstrap.servers"] == "kafka.internal.example:9092"
    )
    error_message = "Equivalent VPC/PRIVATE listeners must deduplicate while public and authenticated endpoints are excluded."
  }
}

run "enabled_mysql_cdc_requires_database_inputs" {
  command = plan

  variables {
    create_mysql_connector = true
    mysql_hostname         = null
    mysql_user             = null
    mysql_password         = null
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

  expect_failures = [terraform_data.mysql_preflight[0]]
}

run "enabled_mysql_cdc_requires_kafka_endpoints" {
  command = plan

  variables {
    create_mysql_connector = true
    mysql_hostname         = "mysql.internal.example"
    mysql_user             = "debezium"
    mysql_password         = "example-test-password"
  }

  expect_failures = [terraform_data.mysql_preflight[0]]
}

run "ambiguous_mysql_private_listeners_are_rejected" {
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

run "public_mysql_history_listener_is_rejected" {
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
        instance_endpoints = [{
          bootstrap_servers = "kafka.public.example:9092"
          network_type      = "INTERNET"
          protocol          = "PLAINTEXT"
        }]
      }
    }
  }

  expect_failures = [terraform_data.mysql_preflight[0]]
}

run "authenticated_mysql_history_listener_is_rejected" {
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
        instance_endpoints = [{
          bootstrap_servers = "kafka.auth.example:9094"
          network_type      = "VPC"
          protocol          = "SASL_SSL"
        }]
      }
    }
  }

  expect_failures = [terraform_data.mysql_preflight[0]]
}
