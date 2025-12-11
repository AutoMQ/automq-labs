terraform {
  required_version = ">= 1.3.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    random = {
      source = "hashicorp/random"
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

provider "azuread" {
  # Uses the same authentication as azurerm provider
}

# Get current Azure AD client configuration
data "azuread_client_config" "current" {}

# Unique suffix to avoid name collisions when creating resources
resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

locals {
  name_suffix          = "${var.env_prefix}-${random_string.suffix.result}"
  storage_account_name = "${var.env_prefix}${random_string.suffix.result}"
  ops_container_name   = "automq-ops-${local.name_suffix}"
  data_container_name  = "automq-data-${local.name_suffix}"

  # Service Principal credentials: Use provided or auto-created
  # Following official ARO demo pattern: use application.client_id and application_password.value
  service_principal_client_id = coalesce(
    var.service_principal_client_id,
    try(azuread_application.openshift[0].client_id, null)
  )
  service_principal_client_secret = coalesce(
    var.service_principal_client_secret,
    try(azuread_application_password.openshift[0].value, null)
  )
}

# Resource group for OpenShift cluster
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    purpose    = "AutoMQ OpenShift Infrastructure"
    managed_by = "terraform"
  }
}

# Network module for OpenShift cluster
module "network" {
  source = "./modules/network"

  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  name_suffix         = local.name_suffix
  vnet_cidr           = var.vnet_cidr
}

# IAM module for Managed Identity
module "iam" {
  source = "./modules/iam"

  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subscription_id     = var.subscription_id
  name_suffix         = local.name_suffix
}

# Service Principal for OpenShift Cluster
# Following official ARO demo pattern: https://github.com/rh-mobb/terraform-aro-permissions

# Create Azure AD Application
resource "azuread_application" "openshift" {
  count        = var.create_openshift_cluster && var.service_principal_client_id == null ? 1 : 0
  display_name = "aro-${var.openshift_cluster_name != null ? var.openshift_cluster_name : local.name_suffix}"
  owners       = [data.azuread_client_config.current.object_id]
}

# Create Application Password (Client Secret)
# NOTE: Use azuread_application_password instead of azuread_service_principal_password
#       This is the recommended approach per official ARO demo
resource "azuread_application_password" "openshift" {
  count          = var.create_openshift_cluster && var.service_principal_client_id == null ? 1 : 0
  display_name   = "aro-${var.openshift_cluster_name != null ? var.openshift_cluster_name : local.name_suffix}"
  application_id = azuread_application.openshift[0].id
}

# Create Service Principal
resource "azuread_service_principal" "openshift" {
  count     = var.create_openshift_cluster && var.service_principal_client_id == null ? 1 : 0
  client_id = azuread_application.openshift[0].client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# Assign Contributor role to Service Principal at subscription level
# NOTE: Using principal_id (object_id) and skip_service_principal_aad_check per official pattern
resource "azurerm_role_assignment" "openshift_contributor" {
  count                            = var.create_openshift_cluster && var.service_principal_client_id == null ? 1 : 0
  scope                            = "/subscriptions/${var.subscription_id}"
  role_definition_name             = "Contributor"
  principal_id                     = azuread_service_principal.openshift[0].object_id
  skip_service_principal_aad_check = true
}

# Get Azure Red Hat OpenShift Resource Provider Service Principal
# This is the service principal that Azure uses to manage ARO clusters
# It is automatically created when you register the Microsoft.RedHatOpenShift provider
data "azuread_service_principal" "aro_resource_provider" {
  count        = var.create_openshift_cluster ? 1 : 0
  display_name = "Azure Red Hat OpenShift RP"
}

# Assign Network Contributor role to ARO Resource Provider Service Principal on VNet
# This is REQUIRED for ARO cluster creation - the resource provider needs VNet permissions
resource "azurerm_role_assignment" "aro_resource_provider_vnet" {
  count                = var.create_openshift_cluster ? 1 : 0
  scope                = module.network.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = data.azuread_service_principal.aro_resource_provider[0].object_id
}


# Storage module for Azure Blob Storage
module "storage" {
  source = "./modules/storage"

  location             = var.location
  resource_group_name  = azurerm_resource_group.rg.name
  storage_account_name = local.storage_account_name
  ops_container_name   = local.ops_container_name
  data_container_name  = local.data_container_name
}

output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.rg.name
}

output "storage_account_name" {
  description = "The name of the storage account for AutoMQ buckets"
  value       = module.storage.storage_account_name
}

output "storage_account_endpoint" {
  description = "The primary blob endpoint of the storage account"
  value       = module.storage.storage_account_endpoint
}

output "automq_data_bucket" {
  description = "The name of the automq-data container"
  value       = local.data_container_name
}

output "automq_ops_bucket" {
  description = "The name of the automq-ops container"
  value       = local.ops_container_name
}

output "workload_identity_client_id" {
  description = "Managed Identity Client ID for Service Principal authentication (use this for AutoMQ Enterprise deployment)"
  value       = module.iam.workload_identity_client_id
}

output "workload_identity_id" {
  description = "Managed Identity Resource ID"
  value       = module.iam.workload_identity_id
}

output "vnet_id" {
  description = "Virtual Network ID for OpenShift cluster"
  value       = module.network.vnet_id
}

output "vnet_name" {
  description = "Virtual Network name"
  value       = module.network.vnet_name
}

output "master_subnet_id" {
  description = "Master subnet ID for OpenShift control plane"
  value       = module.network.master_subnet_id
}

output "worker_subnet_id" {
  description = "Worker subnet ID for OpenShift worker nodes"
  value       = module.network.worker_subnet_id
}

output "automq_subnet_id" {
  description = "AutoMQ dedicated subnet ID for AutoMQ workloads"
  value       = module.network.automq_subnet_id
}
