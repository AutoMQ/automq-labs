variable "location" {
  type        = string
  description = "Azure region"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "subscription_id" {
  type        = string
  description = "Subscription ID for role assignments"
}

variable "name_suffix" {
  type        = string
  description = "Suffix for identity name"
}

# Identity for workloads / nodegroup / console
resource "azurerm_user_assigned_identity" "workload" {
  name                = "uai-workload-${var.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_role_assignment" "workload_storage_blob_data_contributor" {
  role_definition_name = "Storage Blob Data Contributor"
  scope                = "/subscriptions/${var.subscription_id}"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

resource "azurerm_role_assignment" "workload_contributor" {
  role_definition_name = "Contributor"
  scope                = "/subscriptions/${var.subscription_id}"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

output "workload_identity_id" {
  description = "User-assigned managed identity resource ID"
  value       = azurerm_user_assigned_identity.workload.id
}

output "workload_identity_client_id" {
  description = "Client ID of the user-assigned managed identity (use this for Service Principal authentication)"
  value       = azurerm_user_assigned_identity.workload.client_id
}
