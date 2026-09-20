terraform {
  required_version = ">= 1.5.7, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0, < 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

locals {
  automq_config      = jsondecode(base64decode(var.automq_config))
  environment_id     = nonsensitive(local.automq_config.environmentId)
  location           = nonsensitive(local.automq_config.region)
  ops_bucket_id      = nonsensitive(local.automq_config.opsBucket.bucketName)
  name_suffix        = "${var.name_prefix}-${random_string.suffix.result}"
  availability_zones = ["1", "2", "3"]
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = local.location
}

module "aks" {
  source = "./modules/aks"

  location                = local.location
  resource_group_name     = azurerm_resource_group.this.name
  aks_name                = "aks-${local.name_suffix}"
  kubernetes_version      = var.kubernetes_version
  subnet_id               = var.private_subnet_id
  dns_prefix              = "${var.name_prefix}-dns"
  service_cidr            = var.service_cidr
  dns_service_ip          = var.dns_service_ip
  subscription_id         = var.subscription_id
  kubernetes_pricing_tier = var.kubernetes_pricing_tier
  private_access_only     = var.private_access_only
  availability_zones      = local.availability_zones
}

module "nodepool_automq" {
  source = "./modules/nodepool-automq"

  kubernetes_cluster_id = module.aks.kubernetes_cluster_id
  subnet_id             = var.private_subnet_id
  nodepool_name         = var.nodepool.name
  vm_size               = var.nodepool.vm_size
  min_count             = var.nodepool.min_count
  max_count             = var.nodepool.max_count
  node_count            = var.nodepool.node_count
  spot                  = var.nodepool.spot
  orchestrator_version  = module.aks.kubernetes_version
  availability_zones    = local.availability_zones
}

module "automq_console" {
  source = "./modules/automq-console"

  location                    = local.location
  resource_group_name         = azurerm_resource_group.this.name
  vnet_id                     = var.vnet_id
  subnet_id                   = var.public_subnet_id
  automq_config               = var.automq_config
  console_image               = var.console_image
  vm_size                     = var.console_vm_size
  subscription_id             = var.subscription_id
  ops_bucket_id               = local.ops_bucket_id
  kubernetes_cluster_id       = module.aks.kubernetes_cluster_id
  console_allowed_cidr_blocks = var.console_allowed_cidr_blocks
  private_access_only         = var.private_access_only
}

output "environment_id" {
  description = "AutoMQ BYOC environment ID decoded from CONFIG."
  value       = local.environment_id
}

output "region" {
  description = "Azure region decoded from CONFIG."
  value       = local.location
}

output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "aks_name" {
  value = module.aks.aks_name
}

output "kubernetes_cluster_id" {
  description = "AKS cluster full ARM ID used when creating an Instance."
  value       = module.aks.kubernetes_cluster_id
}

output "automq_nodepool_name" {
  value = module.nodepool_automq.nodepool_name
}

output "automq_nodepool_vm_size" {
  value = module.nodepool_automq.vm_size
}

output "private_subnet_id" {
  description = "AKS workload subnet full ARM ID used by the Instance load balancer."
  value       = var.private_subnet_id
}

output "console_endpoint" {
  value = module.automq_console.console_endpoint
}

output "console_initial_username" {
  value = "admin"
}

output "console_initial_password" {
  sensitive = true
  value     = module.automq_console.console_initial_password
}

output "console_initial_access_key" {
  description = "Local Console API access key used by the AutoMQ provider."
  sensitive   = true
  value       = module.automq_console.console_initial_access_key
}

output "console_initial_secret_key" {
  description = "Local Console API secret key used by the AutoMQ provider."
  sensitive   = true
  value       = module.automq_console.console_initial_secret_key
}

output "console_vm_id" {
  value = module.automq_console.console_vm_id
}

output "console_identity_id" {
  description = "Console UAMI full ARM ID."
  value       = module.automq_console.console_identity_id
}

output "ops_bucket_id" {
  description = "Canonical Azure logical Ops Bucket ID in storageAccount:container form."
  value       = local.ops_bucket_id
}

output "ops_bucket_endpoint" {
  value = module.automq_console.ops_bucket_endpoint
}

output "data_bucket_id" {
  description = "Canonical Azure logical data Bucket ID in storageAccount:container form."
  value       = module.automq_console.data_bucket_id
}

output "data_bucket_endpoint" {
  value = module.automq_console.data_bucket_endpoint
}

output "dns_zone_id" {
  description = "Private DNS Zone full ARM ID."
  value       = module.automq_console.dns_zone_id
}

output "dns_zone_name" {
  value = module.automq_console.dns_zone_name
}

output "workload_identity_id" {
  description = "Terraform-provided Data Plane UAMI full ARM ID."
  value       = module.automq_console.workload_identity_id
}

output "workload_identity_client_id" {
  description = "Terraform-provided Data Plane UAMI client ID."
  value       = module.automq_console.workload_identity_client_id
}
