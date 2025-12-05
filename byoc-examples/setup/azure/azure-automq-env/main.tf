terraform {
  required_version = ">= 1.3.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
    random = {
      source = "hashicorp/random"
    }
    tls = {
      source = "hashicorp/tls"
    }
    local = {
      source = "hashicorp/local"
    }
    null = {
      source = "hashicorp/null"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Unique suffix to avoid name collisions when creating resources
resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

locals {
  name_suffix          = "${var.env_prefix}-${random_string.suffix.result}"
  storage_account_name = "sa${var.env_prefix}${random_string.suffix.result}"
  ops_container_name   = "automq-ops-${local.name_suffix}"
  data_container_name  = "automq-data-${local.name_suffix}"
}

# Resource group created for all managed resources
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

module "aks" {
  source = "./modules/aks"

  location                = var.location
  resource_group_name     = azurerm_resource_group.rg.name
  aks_name                = "aks-${local.name_suffix}"
  kubernetes_version      = var.kubernetes_version
  subnet_id               = var.private_subnet_id
  dns_prefix              = "${var.env_prefix}-dns"
  service_cidr            = var.service_cidr
  dns_service_ip          = var.dns_service_ip
  kubeconfig_path         = var.kubeconfig_path
  subscription_id         = var.subscription_id
  kubernetes_pricing_tier = var.kubernetes_pricing_tier
}

module "iam" {
  source = "./modules/iam"

  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subscription_id     = var.subscription_id
  name_suffix         = local.name_suffix
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
  cluster_identity_id   = module.iam.workload_identity_id
}

module "automq_console" {
  source = "./modules/automq-console"

  location             = var.location
  resource_group_name  = azurerm_resource_group.rg.name
  vnet_id              = var.vnet_id
  public_subnet_id     = var.public_subnet_id
  private_subnet_ids   = [var.private_subnet_id]
  storage_account_name = local.storage_account_name
  ops_container_name   = local.ops_container_name
  data_container_name  = local.data_container_name
  image_id             = var.automq_console_id
  vm_size              = var.automq_console_vm_size
  cluster_identity_id  = module.iam.workload_identity_id
  subscription_id      = var.subscription_id
}

output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "aks_name" {
  value = module.aks.aks_name
}

output "automq_nodepool_name" {
  value = module.nodepool_automq.nodepool_name
}

output "automq_console_endpoint" {
  value = module.automq_console.console_endpoint
}

output "automq_console_username" {
  value = module.automq_console.console_initial_username
}

output "automq_console_password" {
  sensitive = true
  value     = module.automq_console.console_initial_password
}

output "dns_zone_name" {
  value = module.automq_console.dns_zone_name
}

# output "dns_zone_id" {
#   value = module.automq_console.dns_zone_id
# }


output "data_bucket_endpoint" {
  value = module.automq_console.data_bucket_endpoint
}

output "nodepool_identity_client_id" {
  description = "Managed Identity Client ID associated with the AutoMQ AKS node pool"
  value       = module.iam.workload_identity_client_id
}

output "storage_account_name" {
  description = "The name of the storage account."
  value       = local.storage_account_name
}

output "automq_data_bucket" {
  description = "The name of the automq-data container."
  value       = local.data_container_name
}

output "automq_ops_bucket" {
  description = "The name of the automq-ops container."
  value       = local.ops_container_name
}

