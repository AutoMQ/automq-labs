terraform {
  required_version = ">= 1.3"

  required_providers {
    automq = {
      source  = "automq/automq"
      version = "= 0.4.8"
    }
  }
}

# Read the endpoint and Service Account credentials from AUTOMQ_BYOC_* variables.
provider "automq" {}

variable "environment_id" {
  type        = string
  description = "ID of the existing Azure BYOC environment."
}

variable "automq_version" {
  type        = string
  description = "Data Plane version supported by the target Console."
}

variable "kubernetes_cluster_id" {
  type        = string
  description = "Full ARM resource ID of the existing AKS cluster."
}

variable "load_balancer_subnet_id" {
  type        = string
  description = "Full ARM resource ID of the private load balancer subnet."
}

variable "instance_type" {
  type        = string
  description = "Instance type offered by the Console for the target node pool."
}

variable "node_pool_name" {
  type        = string
  description = "Name of the existing AutoMQ AKS node pool."
}

variable "deploy_type" {
  # Provider 0.4.8 rejects unknown cluster IDs when deploy_type is a literal.
  # Keep both as inputs so they are validated together after plan evaluation.
  type        = string
  description = "Deployment type; this Azure example supports K8S only."
  default     = "K8S"
  validation {
    condition     = var.deploy_type == "K8S"
    error_message = "This Azure example supports K8S only."
  }
}

variable "zones" {
  description = "Three distinct zone IDs from the Console, matching the AKS node pool."
  type        = list(string)
  validation {
    condition     = length(var.zones) == 3 && length(distinct(var.zones)) == 3
    error_message = "Provide three distinct availability zone IDs."
  }
}

resource "automq_kafka_instance" "demo" {
  environment_id = var.environment_id
  name           = "azure-managed-demo"
  description    = "Azure managed three zone demo"
  version        = var.automq_version

  compute_specs = {
    deploy_type         = var.deploy_type
    pricing_mode        = "UsageBased"
    reserved_node_count = 3
    instance_types      = [var.instance_type]

    kubernetes_cluster_id            = var.kubernetes_cluster_id
    kubernetes_load_balancer_subnets = [var.load_balancer_subnet_id]
    networks = [for zone in var.zones : {
      zone    = zone
      subnets = [] # AKS workload zones come from the node pool.
    }]

    schedule_spec = yamlencode({
      nodeSelector = {
        "kubernetes.azure.com/agentpool" = var.node_pool_name
      }
      tolerations = [{
        key      = "dedicated"
        operator = "Equal"
        value    = "automq"
        effect   = "NoSchedule"
      }]
    })

    # Omit data_buckets, instance_role, and dns_zone for Control Plane management.
    # Do not supply the environment setup's customer-provided resource outputs.
    # The Control Plane also assigns the namespace and ServiceAccount.
  }

  features = {
    wal_mode = "S3WAL" # Object-storage WAL uses Azure Blob in this environment.
    security = {
      authentication_methods   = ["sasl"]
      transit_encryption_modes = ["plaintext"]
    }
  }
}

output "instance_id" {
  value = automq_kafka_instance.demo.id
}

output "endpoints" {
  value = automq_kafka_instance.demo.endpoints
}
