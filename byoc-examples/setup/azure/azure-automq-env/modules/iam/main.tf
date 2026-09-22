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

variable "ops_storage_container_id" {
  type        = string
  description = "Ops Blob Container full ARM ID"
}

variable "data_storage_container_id" {
  type        = string
  description = "Data Blob Container full ARM ID"
}

variable "dns_zone_id" {
  type        = string
  description = "Private DNS Zone full ARM ID"
}

variable "kubernetes_cluster_id" {
  type        = string
  description = "AKS cluster full ARM ID"
}

variable "kubernetes_namespace" {
  type        = string
  description = "Optional Kubernetes namespace for Workload Identity federation"
  default     = ""
}

variable "kubernetes_service_account" {
  type        = string
  description = "Optional Kubernetes ServiceAccount for Workload Identity federation"
  default     = ""
}

data "azurerm_kubernetes_cluster" "selected" {
  name                = split("/", var.kubernetes_cluster_id)[8]
  resource_group_name = split("/", var.kubernetes_cluster_id)[4]
}

locals {
  subscription_scope = "/subscriptions/${var.subscription_id}"
  node_resource_group_scope = join("/", [
    local.subscription_scope,
    "resourceGroups",
    data.azurerm_kubernetes_cluster.selected.node_resource_group,
  ])
  create_federated_identity = trimspace(var.kubernetes_namespace) != "" && trimspace(var.kubernetes_service_account) != ""
}

# Identity used by AutoMQ workloads through AKS Workload Identity.
resource "azurerm_user_assigned_identity" "workload" {
  name                = "uai-workload-${var.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_role_definition" "workload_blob_runtime" {
  name        = "AutoMQ ${var.name_suffix} Blob Runtime"
  scope       = local.subscription_scope
  description = "AutoMQ Blob runtime access for the selected data and ops containers."

  permissions {
    actions = []
    data_actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete",
    ]
    not_actions      = []
    not_data_actions = []
  }

  assignable_scopes = [local.subscription_scope]
}

resource "azurerm_role_assignment" "workload_blob_runtime" {
  for_each = {
    ops  = var.ops_storage_container_id
    data = var.data_storage_container_id
  }

  scope              = each.value
  role_definition_id = azurerm_role_definition.workload_blob_runtime.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.workload.principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_definition" "workload_dns_runtime" {
  name        = "AutoMQ ${var.name_suffix} DNS Runtime"
  scope       = local.subscription_scope
  description = "AutoMQ Private DNS record access for the selected zone."

  permissions {
    actions = [
      "Microsoft.Network/privateDnsZones/read",
      "Microsoft.Network/privateDnsZones/virtualNetworkLinks/read",
      "Microsoft.Network/privateDnsZones/A/read",
      "Microsoft.Network/privateDnsZones/A/write",
      "Microsoft.Network/privateDnsZones/A/delete",
    ]
    not_actions = []
  }

  assignable_scopes = [local.subscription_scope]
}

resource "azurerm_role_assignment" "workload_dns_runtime" {
  scope              = var.dns_zone_id
  role_definition_id = azurerm_role_definition.workload_dns_runtime.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.workload.principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_definition" "workload_node_disk_runtime" {
  name        = "AutoMQ ${var.name_suffix} Node Disk Runtime"
  scope       = local.subscription_scope
  description = "AutoMQ node disk failover access for the selected AKS Node Resource Group."

  permissions {
    actions = [
      "Microsoft.Compute/disks/read",
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/attachDisk/action",
      "Microsoft.Compute/virtualMachines/detachDisk/action",
      "Microsoft.Compute/virtualMachines/write",
      "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/read",
      "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/write",
    ]
    not_actions = []
  }

  assignable_scopes = [local.subscription_scope]
}

resource "azurerm_role_assignment" "workload_node_disk_runtime" {
  scope              = local.node_resource_group_scope
  role_definition_id = azurerm_role_definition.workload_node_disk_runtime.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.workload.principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_federated_identity_credential" "workload" {
  count = local.create_federated_identity ? 1 : 0

  name = substr(
    "automq-${replace(var.kubernetes_service_account, "/[^a-zA-Z0-9-]/", "-")}-${var.name_suffix}",
    0,
    120,
  )
  user_assigned_identity_id = azurerm_user_assigned_identity.workload.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = data.azurerm_kubernetes_cluster.selected.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.kubernetes_namespace}:${var.kubernetes_service_account}"
}

output "aks_identity_id" {
  value = null
}

output "aks_identity_client_id" {
  value = null
}

output "workload_identity_id" {
  value = azurerm_user_assigned_identity.workload.id
}

output "workload_identity_client_id" {
  value = azurerm_user_assigned_identity.workload.client_id
}
