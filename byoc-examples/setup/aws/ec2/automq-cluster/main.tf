data "http" "console_capabilities" {
  url                = "${trimsuffix(var.console_endpoint, "/")}/auth/login"
  request_timeout_ms = 15000
}

locals {
  normalized_wal_mode = upper(var.wal_mode)
  selected_broker_networks = slice(
    var.broker_networks,
    0,
    min(var.availability_zone_count, length(var.broker_networks)),
  )
}

resource "terraform_data" "console_health_preflight" {
  lifecycle {
    precondition {
      condition     = data.http.console_capabilities.status_code == 200
      error_message = "AutoMQ Console health check failed. The /auth/login endpoint must return HTTP 200 before Terraform creates an Instance."
    }
  }
}

resource "automq_kafka_instance" "this" {
  depends_on = [terraform_data.console_health_preflight]

  environment_id = var.environment_id
  name           = var.instance_name
  description    = var.instance_description
  version        = var.automq_version
  tags           = var.tags

  compute_specs = {
    reserved_node_count = var.reserved_node_count
    instance_types      = [var.broker_instance_type]
    # Provider 0.4.6 treats an unknown reserved_node_count as missing during
    # terraform validate. This expression defers pricing_mode with that input;
    # variable validation enforces 3-100, so apply always resolves UsageBased.
    pricing_mode = var.reserved_node_count >= 3 ? "UsageBased" : null
    deploy_type  = "IAAS"

    networks = local.selected_broker_networks
    # Keep the object unknown until the bucket input resolves; Provider 0.4.6
    # otherwise validates bucket_name before root variables are available.
    data_buckets = trimspace(var.data_bucket_name) != "" ? [{
      bucket_name = var.data_bucket_name
    }] : null
    dns_zone      = var.dns_zone_id
    instance_role = var.instance_role_name
    file_system_param = local.normalized_wal_mode == "FSWAL" ? {
      file_system_type                 = "EFS_PROVISIONED"
      throughput_mibps_per_file_system = var.efs_wal_throughput_mibps_per_file_system
      file_system_count                = 1
    } : null
  }

  features = {
    wal_mode         = local.normalized_wal_mode
    instance_configs = var.instance_configs

    security = {
      authentication_methods   = var.authentication_methods
      transit_encryption_modes = var.transit_encryption_modes
      data_encryption_mode     = var.data_encryption_mode
    }

    schema_registry_enabled = var.schema_registry_enabled
  }

  lifecycle {
    precondition {
      condition     = length(local.selected_broker_networks) == var.availability_zone_count
      error_message = "broker_networks does not contain enough networks for availability_zone_count. Run configure-from-console.sh again or provide one network for single-AZ and three networks for multi-AZ deployment."
    }

    precondition {
      condition     = local.normalized_wal_mode != "EBSWAL" || var.availability_zone_count == 1
      error_message = "EBSWAL is supported only with availability_zone_count = 1 in this quick-start. Use S3WAL or FSWAL for a three-AZ deployment."
    }

    precondition {
      condition     = local.normalized_wal_mode != "FSWAL" || var.availability_zone_count == 3
      error_message = "FSWAL with EFS requires availability_zone_count = 3 in this quick-start."
    }
  }

  timeouts {
    create = "30m"
    delete = "30m"
  }
}
