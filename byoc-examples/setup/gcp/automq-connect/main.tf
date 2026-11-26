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
