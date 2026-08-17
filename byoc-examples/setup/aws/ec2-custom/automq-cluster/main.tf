data "http" "console_capabilities" {
  url                = "${trimsuffix(var.console_endpoint, "/")}/auth/login"
  request_timeout_ms = 15000
}

locals {
  usage_based_pricing_available = can(regex(
    "\"usageBasedPricingAvailable\"\\s*:\\s*true",
    data.http.console_capabilities.response_body,
  ))
}

resource "terraform_data" "usage_based_subscription_preflight" {
  lifecycle {
    precondition {
      condition     = data.http.console_capabilities.status_code == 200 && local.usage_based_pricing_available
      error_message = "The Console reports that Usage Based billing is unavailable. In AutoMQ Cloud, open Billing > Overview and activate a valid Free Trial or AWS Marketplace payment method before creating an Instance."
    }
  }
}

resource "automq_kafka_instance" "this" {
  depends_on = [terraform_data.usage_based_subscription_preflight]

  environment_id = var.environment_id
  name           = var.instance_name
  description    = var.instance_description
  version        = var.automq_version
  tags           = var.tags

  compute_specs = {
    reserved_node_count = var.reserved_node_count
    instance_types      = [var.broker_instance_type]
    # Keep both UsageBased fields unknown until the node count resolves so
    # Provider 0.4.5 validates the complete sizing tuple.
    pricing_mode = var.reserved_node_count >= 3 ? "UsageBased" : null
    deploy_type  = "IAAS"

    networks = var.broker_networks
    # Keep the object unknown until the bucket input resolves; Provider 0.4.5
    # otherwise validates bucket_name before root variables are available.
    data_buckets = trimspace(var.data_bucket_name) != "" ? [{
      bucket_name = var.data_bucket_name
    }] : null
    dns_zone      = var.dns_zone_id
    instance_role = var.instance_role_name
  }

  features = {
    wal_mode         = upper(var.wal_mode)
    instance_configs = var.instance_configs

    security = {
      authentication_methods   = var.authentication_methods
      transit_encryption_modes = var.transit_encryption_modes
      data_encryption_mode     = var.data_encryption_mode
    }

    schema_registry_enabled = var.schema_registry_enabled
  }

  timeouts {
    create = "30m"
    delete = "30m"
  }
}
