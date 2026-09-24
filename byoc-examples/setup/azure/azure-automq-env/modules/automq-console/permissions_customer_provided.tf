# Console permissions for customer-provided resources. Keep ARM management
# actions separate from Kubernetes API authorization: the AKS management role
# only obtains clusterUser credentials, while the Azure RBAC Cluster Admin
# assignment grants the Kubernetes verbs used by Helm.
locals {
  console_subscription_scope = "/subscriptions/${var.subscription_id}"
  console_resource_group_scope = join("/", [
    local.console_subscription_scope,
    "resourceGroups",
    var.resource_group_name,
  ])
  console_role_suffix = substr(var.storage_account_name, 0, 24)
  customer_blob_scopes = {
    ops  = azurerm_storage_container.automq_ops.id
    data = azurerm_storage_container.automq_data.id
  }
  console_required_aks_cluster_admin_scopes = [var.kubernetes_cluster_id]
}

resource "azurerm_role_definition" "console_required_read" {
  name        = "AutoMQ Console ${local.console_role_suffix} Required Read"
  scope       = local.console_subscription_scope
  description = "Management-plane reads required by AutoMQ Console system initialization and resource discovery."

  permissions {
    actions = [
      "Microsoft.Resources/subscriptions/read",
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachineScaleSets/read",
      "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/read",
      "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/networkInterfaces/read",
      "Microsoft.Network/networkInterfaces/read",
      "Microsoft.Storage/checknameavailability/read",
      "Microsoft.Storage/storageAccounts/read",
      "Microsoft.Storage/storageAccounts/managementPolicies/read",
      "Microsoft.Storage/storageAccounts/blobServices/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/read",
      "Microsoft.Network/virtualNetworks/read",
      "Microsoft.Network/virtualNetworks/subnets/read",
      "Microsoft.Network/privateDnsZones/read",
      "Microsoft.Network/privateDnsZones/virtualNetworkLinks/read",
      "Microsoft.ContainerService/managedClusters/read",
      "Microsoft.ContainerService/managedClusters/agentPools/read",
      "Microsoft.ManagedIdentity/userAssignedIdentities/read",
      "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/read",
      "Microsoft.Authorization/roleAssignments/read",
      "Microsoft.Authorization/roleDefinitions/read",
      "Microsoft.Authorization/permissions/read",
    ]
    not_actions = []
  }

  assignable_scopes = [local.console_subscription_scope]
}

resource "azurerm_role_assignment" "console_required_read" {
  scope              = local.console_subscription_scope
  role_definition_id = azurerm_role_definition.console_required_read.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.console.principal_id
}

resource "azurerm_role_definition" "console_required_blob_data" {
  name        = "AutoMQ Console ${local.console_role_suffix} Blob Data"
  scope       = local.console_subscription_scope
  description = "Blob object operations required by AutoMQ Console."

  permissions {
    actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/read",
    ]
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

resource "azurerm_role_assignment" "console_required_blob_data" {
  for_each = local.customer_blob_scopes

  scope              = each.value
  role_definition_id = azurerm_role_definition.console_required_blob_data.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.console.principal_id
}

resource "azurerm_role_definition" "console_required_dns_records" {
  name        = "AutoMQ Console ${local.console_role_suffix} DNS Records"
  scope       = local.console_subscription_scope
  description = "Private DNS record operations required by AutoMQ Console."

  permissions {
    actions = [
      "Microsoft.Network/privateDnsZones/read",
      "Microsoft.Network/privateDnsZones/virtualNetworkLinks/read",
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

resource "azurerm_role_assignment" "console_required_dns_records" {
  scope              = azurerm_private_dns_zone.zone.id
  role_definition_id = azurerm_role_definition.console_required_dns_records.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.console.principal_id
}

resource "azurerm_role_definition" "console_required_aks_access" {
  name        = "AutoMQ Console ${local.console_role_suffix} AKS Access"
  scope       = local.console_subscription_scope
  description = "AKS management actions for non-admin cluster-user access."

  permissions {
    actions = [
      "Microsoft.ContainerService/managedClusters/read",
      "Microsoft.ContainerService/managedClusters/listClusterUserCredential/action",
    ]
    not_actions = []
  }

  assignable_scopes = [local.console_subscription_scope]
}

resource "azurerm_role_assignment" "console_required_aks_access" {
  # Exact AKS scope: this grants ARM read and clusterUser credential access.
  scope              = var.kubernetes_cluster_id
  role_definition_id = azurerm_role_definition.console_required_aks_access.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.console.principal_id
}

resource "azurerm_role_assignment" "console_required_aks_cluster_admin" {
  # The list currently contains one selected AKS; keep it list-shaped for the
  # same late-bound scope model used by the playground permissions module.
  for_each             = { for index, scope in local.console_required_aks_cluster_admin_scopes : index => scope }
  scope                = each.value
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = azurerm_user_assigned_identity.console.principal_id
}
