locals {
  managed_blob_metadata_key   = "automqvendor"
  managed_blob_metadata_value = "automq"
}

resource "azurerm_role_definition" "console_managed_storage" {
  name        = "AutoMQ Console ${local.console_role_suffix} Managed Storage"
  scope       = local.console_subscription_scope
  description = "Storage Account and Blob Container lifecycle operations for managed resources."

  permissions {
    actions = [
      "Microsoft.Storage/storageAccounts/read",
      "Microsoft.Storage/storageAccounts/write",
      "Microsoft.Storage/storageAccounts/delete",
      "Microsoft.Storage/storageAccounts/blobServices/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/write",
      "Microsoft.Storage/storageAccounts/blobServices/containers/delete",
    ]
    not_actions = []
  }

  assignable_scopes = [local.console_subscription_scope]
}

resource "azurerm_role_assignment" "console_managed_storage" {
  scope              = local.console_resource_group_scope
  role_definition_id = azurerm_role_definition.console_managed_storage.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.console.principal_id
}

resource "azurerm_role_definition" "console_managed_dns" {
  name        = "AutoMQ Console ${local.console_role_suffix} Managed DNS"
  scope       = local.console_subscription_scope
  description = "Private DNS Zone, VNet link, and record lifecycle operations."

  permissions {
    actions = [
      "Microsoft.Network/privateDnsZones/read",
      "Microsoft.Network/privateDnsZones/write",
      "Microsoft.Network/privateDnsZones/delete",
      "Microsoft.Network/privateDnsZones/virtualNetworkLinks/read",
      "Microsoft.Network/privateDnsZones/virtualNetworkLinks/write",
      "Microsoft.Network/privateDnsZones/virtualNetworkLinks/delete",
      "Microsoft.Network/virtualNetworks/join/action",
      "Microsoft.Network/privateDnsZones/A/read",
      "Microsoft.Network/privateDnsZones/A/write",
      "Microsoft.Network/privateDnsZones/A/delete",
      "Microsoft.Network/privateDnsZones/CNAME/read",
      "Microsoft.Network/privateDnsZones/CNAME/write",
      "Microsoft.Network/privateDnsZones/CNAME/delete",
    ]
    not_actions = []
  }

  assignable_scopes = [local.console_subscription_scope]
}

resource "azurerm_role_assignment" "console_managed_dns" {
  scope              = local.console_resource_group_scope
  role_definition_id = azurerm_role_definition.console_managed_dns.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.console.principal_id
}

resource "azurerm_role_definition" "console_managed_uami" {
  name        = "AutoMQ Console ${local.console_role_suffix} Managed UAMI"
  scope       = local.console_subscription_scope
  description = "User-Assigned Managed Identity and Federated Identity Credential lifecycle operations."

  permissions {
    actions = [
      "Microsoft.ManagedIdentity/userAssignedIdentities/read",
      "Microsoft.ManagedIdentity/userAssignedIdentities/write",
      "Microsoft.ManagedIdentity/userAssignedIdentities/delete",
      "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/read",
      "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/write",
      "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/delete",
    ]
    not_actions = []
  }

  assignable_scopes = [local.console_subscription_scope]
}

resource "azurerm_role_assignment" "console_managed_uami" {
  scope              = local.console_resource_group_scope
  role_definition_id = azurerm_role_definition.console_managed_uami.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.console.principal_id
}

resource "azurerm_role_definition" "console_managed_target_blob_data" {
  name        = "AutoMQ Console ${local.console_role_suffix} Managed Blob Data"
  scope       = local.console_subscription_scope
  description = "Blob object operations for AutoMQ-managed containers."

  permissions {
    actions     = []
    not_actions = []
    data_actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete",
    ]
    not_data_actions = []
  }

  assignable_scopes = [local.console_subscription_scope]
}

resource "azurerm_role_assignment" "console_managed_target_blob_data" {
  scope              = local.console_resource_group_scope
  role_definition_id = azurerm_role_definition.console_managed_target_blob_data.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.console.principal_id
  condition_version  = "2.0"
  condition          = <<-EOT
    @Resource[Microsoft.Storage/storageAccounts/blobServices/containers/metadata:${local.managed_blob_metadata_key}] StringEquals '${local.managed_blob_metadata_value}'
  EOT
}

resource "azurerm_role_definition" "console_managed_rbac_delegation" {
  name        = "AutoMQ Console ${local.console_role_suffix} RBAC Delegation"
  scope       = local.console_subscription_scope
  description = "Role Definition and Role Assignment lifecycle operations."

  permissions {
    actions = [
      "Microsoft.Authorization/roleAssignments/read",
      "Microsoft.Authorization/roleAssignments/write",
      "Microsoft.Authorization/roleAssignments/delete",
      "Microsoft.Authorization/roleDefinitions/read",
      "Microsoft.Authorization/roleDefinitions/write",
      "Microsoft.Authorization/roleDefinitions/delete",
    ]
    not_actions = []
  }

  assignable_scopes = [local.console_subscription_scope]
}

resource "azurerm_role_assignment" "console_managed_rbac_delegation" {
  scope              = local.console_subscription_scope
  role_definition_id = azurerm_role_definition.console_managed_rbac_delegation.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.console.principal_id
  condition_version  = "2.0"
  condition          = <<-EOT
    ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR
      @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'})
    AND
    ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR
      @Resource[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'})
  EOT
}
