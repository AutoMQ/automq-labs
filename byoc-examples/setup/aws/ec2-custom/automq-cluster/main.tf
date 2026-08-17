locals {
  broker_networks = [
    for zone in sort(keys(var.private_subnet_ids_by_zone)) : {
      zone    = zone
      subnets = var.private_subnet_ids_by_zone[zone]
    }
  ]
}

resource "automq_kafka_instance" "this" {
  environment_id = var.environment_id
  name           = var.instance_name
  description    = var.instance_description
  version        = var.automq_version
  tags           = var.tags

  # Provider 0.4.5 validates literal partial objects before root variables resolve.
  compute_specs = {
    reserved_aku = var.reserved_aku
    pricing_mode = var.reserved_aku >= 3 ? "SubscriptionBased" : null
    deploy_type  = "IAAS"

    networks = local.broker_networks
    data_buckets = trimspace(var.data_bucket_name) != "" ? [{
      bucket_name = var.data_bucket_name
    }] : null
    dns_zone      = var.dns_zone_id
    instance_role = var.instance_role_arn
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
