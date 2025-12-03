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

resource "azurerm_user_assigned_identity" "automq" {
  name                = "uai-automq-${var.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_role_assignment" "storage_blob_data_contributor" {
  role_definition_name = "Storage Blob Data Contributor"
  scope                = "/subscriptions/${var.subscription_id}"
  principal_id         = azurerm_user_assigned_identity.automq.principal_id
}

resource "azurerm_role_assignment" "contributor" {
  role_definition_name = "Contributor"
  scope                = "/subscriptions/${var.subscription_id}"
  principal_id         = azurerm_user_assigned_identity.automq.principal_id
}

output "identity_id" {
  value = azurerm_user_assigned_identity.automq.id
}

output "identity_client_id" {
  value = azurerm_user_assigned_identity.automq.client_id
}
