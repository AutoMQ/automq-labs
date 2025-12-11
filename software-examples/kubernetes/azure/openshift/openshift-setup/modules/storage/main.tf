variable "location" {
  type        = string
  description = "Azure region"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "storage_account_name" {
  type        = string
  description = "Name of the storage account"
}

variable "ops_container_name" {
  type        = string
  description = "Name of the operations container"
}

variable "data_container_name" {
  type        = string
  description = "Name of the data container"
}

# Azure Storage Account for AutoMQ Blob Storage
resource "azurerm_storage_account" "automq" {
  name                     = var.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind              = "StorageV2"

  # Security settings
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public  = false
  shared_access_key_enabled       = true

  # Enable blob storage
  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  tags = {
    purpose = "AutoMQ Enterprise Storage"
  }
}

# Container for AutoMQ operations data
resource "azurerm_storage_container" "automq_ops" {
  name                  = var.ops_container_name
  storage_account_id    = azurerm_storage_account.automq.id
}

# Container for AutoMQ data
resource "azurerm_storage_container" "automq_data" {
  name                  = var.data_container_name
  storage_account_id    = azurerm_storage_account.automq.id
}

output "storage_account_name" {
  value = azurerm_storage_account.automq.name
}

output "storage_account_endpoint" {
  description = "Primary blob endpoint for Azure Blob Storage"
  value       = azurerm_storage_account.automq.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account (sensitive)"
  value       = azurerm_storage_account.automq.primary_access_key
  sensitive   = true
}

