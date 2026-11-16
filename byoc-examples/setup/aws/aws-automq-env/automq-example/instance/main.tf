terraform {
  required_version = ">= 1.9.0"
  required_providers {
    automq = { source = "automq/automq", version = "= 0.4.8" }
  }
}
# AUTOMQ_BYOC_ENDPOINT, AUTOMQ_BYOC_ACCESS_KEY, AUTOMQ_BYOC_SECRET_KEY.
provider "automq" {}
variable "infrastructure_state_path" {
  type    = string
  default = "../../infrastructure/terraform.tfstate"
}
variable "automq_version" {
  description = "Data-plane version available in the initialized Console; this is not the Console 8.x version."
  type        = string
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.automq_version)) && !startswith(var.automq_version, "8.")
    error_message = "Select an available data-plane release, not a Console 8.x version."
  }
}
variable "instance_name" {
  type    = string
  default = "aws-eks-managed-demo"
}
variable "instance_type" {
  type    = string
  default = "m7g.xlarge"
}
data "terraform_remote_state" "infrastructure" {
  backend = "local"
  config  = { path = var.infrastructure_state_path }
}
locals { infra = data.terraform_remote_state.infrastructure.outputs }
locals {
  instance_compute_specs = {
    # Provider 0.4.8 eagerly validates a known K8S literal against unknown remote-state
    # fields during validate; defer it until the cluster identity is available.
    deploy_type                      = local.infra.cluster_name == "" ? null : "K8S"
    pricing_mode                     = "UsageBased"
    reserved_node_count              = 3
    instance_types                   = [var.instance_type]
    kubernetes_cluster_id            = local.infra.cluster_name
    kubernetes_load_balancer_subnets = values(local.infra.private_subnet_ids_by_az)
    networks                         = [for az, subnet in local.infra.private_subnet_ids_by_az : { zone = az, subnets = [subnet] }]
    schedule_spec = yamlencode({
      affinity = {
        nodeAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = {
            nodeSelectorTerms = [{
              matchExpressions = [for key, value in local.infra.automq_node_selector : {
                key = key, operator = "In", values = [value]
              }]
            }]
          }
        }
      }
      tolerations = local.infra.automq_tolerations
    })
    # Omit Data Bucket, Role, DNS, namespace and KSA: CMP owns their lifecycle.
  }
}
resource "automq_kafka_instance" "demo" {
  environment_id = local.infra.environment_id
  name           = var.instance_name
  description    = "Managed three AZ EKS evaluation"
  version        = var.automq_version
  compute_specs  = local.instance_compute_specs
  features = {
    wal_mode = "S3WAL"
    security = { authentication_methods = ["sasl"], transit_encryption_modes = ["plaintext"] }
  }
  lifecycle {
    precondition {
      condition     = length(trimspace(local.infra.cluster_name)) > 0 && length(local.infra.private_subnet_ids_by_az) == 3 && length(distinct(values(local.infra.private_subnet_ids_by_az))) == 3
      error_message = "Instance requires three distinct AZ/private NLB subnet pairs."
    }
  }
}
output "instance_id" { value = automq_kafka_instance.demo.id }
output "environment_id" { value = local.infra.environment_id }
output "endpoints" { value = automq_kafka_instance.demo.endpoints }
