terraform {
  required_providers {
    automq = {
      source = "automq/automq"
    }
    aws = {
      source = "hashicorp/aws"
    }
  }
}

data "aws_subnets" "aws_subnets_example" {
  provider = aws
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "availability-zone"
    values = [var.az]
  }
}


resource "automq_integration" "prometheus_remote_write_integration" {
  environment_id = var.automq_environment_id
  name           = var.prometheus_integration_name
  type           = var.prometheus_integration_type
  endpoint       = var.prometheus_remote_write_endpoint
  deploy_profile = var.automq_deploy_profile_name

  prometheus_remote_write_config = {
    auth_type = var.prometheus_auth_type
  }
}

provider "automq" {
  automq_byoc_endpoint      = var.automq_byoc_endpoint
  automq_byoc_access_key_id = var.automq_byoc_access_key_id
  automq_byoc_secret_key    = var.automq_byoc_secret_key
}

data "automq_deploy_profile" "automq_deploy_profile" {
  environment_id = var.automq_environment_id
  name           = var.automq_deploy_profile_name
}

data "automq_data_bucket_profiles" "automq_data_bucket_profiles" {
  environment_id = var.automq_environment_id
  profile_name   = data.automq_deploy_profile.automq_deploy_profile.name
}

resource "automq_kafka_instance" "automq_kafka_instance" {
  environment_id = var.automq_environment_id
  name           = var.kafka_instance_name
  description    = var.kafka_instance_description
  version        = var.kafka_version
  deploy_profile = data.automq_deploy_profile.automq_deploy_profile.name

  compute_specs = {
    reserved_aku = var.kafka_reserved_aku
    networks = [
      {
        zone    = var.az
        subnets = [data.aws_subnets.aws_subnets_example.ids[0]]
      }
    ]
    kubernetes_node_groups = [{
      id = var.kubernetes_node_group_id
    }]
    bucket_profiles = [
      {
        id = data.automq_data_bucket_profiles.automq_data_bucket_profiles.data_buckets[0].id
      }
    ]
  }

  features = {
    wal_mode = var.kafka_wal_mode
    security = {
      authentication_methods   = var.kafka_authentication_methods
      transit_encryption_modes = var.kafka_transit_encryption_modes
    }
    instance_configs = var.kafka_instance_configs
    integrations = [
      automq_integration.prometheus_remote_write_integration.id,
    ]
  }

  depends_on = [automq_integration.prometheus_remote_write_integration]
}


# Prometheus Integration Configuration
variable "prometheus_integration_name" {
  description = "Name of the Prometheus remote write integration"
  type        = string
  default     = "prometheus-remote-write"
}

variable "prometheus_integration_type" {
  description = "Type of the Prometheus integration"
  type        = string
  default     = "prometheusRemoteWrite"
}

variable "prometheus_remote_write_endpoint" {
  description = "Prometheus remote write endpoint URL"
  type        = string
  default     = "http://prometheus-prometheus-server.monitoring:9090/api/v1/write"
}

variable "prometheus_auth_type" {
  description = "Authentication type for Prometheus remote write"
  type        = string
  default     = "noauth"
}

# AutoMQ Deploy Profile Configuration
variable "automq_deploy_profile_name" {
  description = "Name of the AutoMQ deploy profile"
  type        = string
  default     = "eks"
}

# Kafka Instance Configuration
variable "kafka_instance_name" {
  description = "Name of the AutoMQ Kafka instance"
  type        = string
  default     = "automq-kafka-benchmark"
}

variable "kafka_instance_description" {
  description = "Description of the AutoMQ Kafka instance"
  type        = string
  default     = "AutoMQ Kafka instance for benchmark testing"
}

variable "kafka_version" {
  description = "Version of the AutoMQ Kafka instance"
  type        = string
  default     = "1.4.1"
}

variable "kafka_reserved_aku" {
  description = "Reserved AKU (AutoMQ Kafka Units) for the instance"
  type        = number
  default     = 3
}

variable "kubernetes_node_group_id" {
  description = "ID of the Kubernetes node group for AutoMQ deployment"
  type        = string
  default     = "automq-node-group"
}

variable "kafka_wal_mode" {
  description = "WAL (Write-Ahead Log) mode for Kafka"
  type        = string
  default     = "EBSWAL"
}

variable "kafka_authentication_methods" {
  description = "Authentication methods for Kafka"
  type        = list(string)
  default     = ["anonymous"]
}

variable "kafka_transit_encryption_modes" {
  description = "Transit encryption modes for Kafka"
  type        = list(string)
  default     = ["plaintext"]
}

variable "kafka_instance_configs" {
  description = "Instance configuration parameters for Kafka"
  type        = map(string)
  default = {
    "auto.create.topics.enable" = "false"
    "log.retention.ms"          = "3600000"
  }
}

# Existing variables
variable "vpc_id" {
  description = "VPC ID where AutoMQ resources will be deployed"
  type        = string
}

variable "region" {
  description = "AWS region for deployment"
  type        = string
}

variable "az" {
  description = "Availability zone for deployment"
  type        = string
}

variable "automq_byoc_endpoint" {
  description = "AutoMQ BYOC endpoint URL"
  type        = string
}

variable "automq_byoc_access_key_id" {
  description = "AutoMQ BYOC access key ID"
  type        = string
  sensitive   = true
}

variable "automq_byoc_secret_key" {
  description = "AutoMQ BYOC secret key"
  type        = string
  sensitive   = true
}

variable "automq_environment_id" {
  description = "AutoMQ environment ID"
  type        = string
}

provider "aws" {
  region = var.region
}