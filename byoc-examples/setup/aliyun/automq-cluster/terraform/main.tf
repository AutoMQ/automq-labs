terraform {
  required_version = ">= 1.3"

  required_providers {
    automq = {
      source  = "automq/automq"
      version = "~> 0.4.8"
    }
  }
}

provider "automq" {
  automq_byoc_endpoint      = var.automq_byoc_endpoint
  automq_byoc_access_key_id = var.automq_byoc_access_key_id
  automq_byoc_secret_key    = var.automq_byoc_secret_key
}

resource "automq_kafka_instance" "elastic_pool" {
  environment_id = var.environment_id
  name           = var.instance_name
  description    = var.instance_description
  version        = var.automq_version

  tags = var.tags

  compute_specs = {
    # The AutoMQ Provider represents VMIS mode as IAAS.
    deploy_type  = "IAAS"
    pricing_mode = var.pricing_mode
    reserved_aku = var.reserved_aku

    # An Alibaba Cloud VSwitch ID is the subnet ID expected here.
    networks        = var.networks
    security_groups = var.security_group_ids
    data_buckets    = var.data_buckets
    dns_zone        = var.dns_zone_id
    instance_role   = var.ram_role_name
  }

  features = {
    # EBSWAL maps to Alibaba Cloud Regional ESSD-backed WAL.
    wal_mode = "EBSWAL"

    security = {
      authentication_methods   = ["anonymous"]
      transit_encryption_modes = ["plaintext"]
    }
  }

  timeouts {
    create = "30m"
    delete = "30m"
  }
}

output "elastic_pool_id" {
  description = "AutoMQ Instance ID of the Elastic Pool."
  value       = automq_kafka_instance.elastic_pool.id
}

output "elastic_pool_status" {
  description = "Provisioning status of the Elastic Pool."
  value       = automq_kafka_instance.elastic_pool.status
}

output "elastic_pool_endpoints" {
  description = "Kafka client endpoints of the Elastic Pool."
  value       = automq_kafka_instance.elastic_pool.endpoints
}
