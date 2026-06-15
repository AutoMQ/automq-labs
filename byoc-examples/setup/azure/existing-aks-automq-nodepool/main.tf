provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

data "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_name
  resource_group_name = var.aks_resource_group_name
}

locals {
  orchestrator_version = coalesce(var.orchestrator_version, data.azurerm_kubernetes_cluster.aks.kubernetes_version)
}

resource "azurerm_kubernetes_cluster_node_pool" "automq" {
  name                  = var.nodepool_name
  kubernetes_cluster_id = data.azurerm_kubernetes_cluster.aks.id
  vm_size               = var.vm_size
  vnet_subnet_id        = var.subnet_id
  orchestrator_version  = local.orchestrator_version

  auto_scaling_enabled = var.auto_scaling_enabled
  min_count            = var.auto_scaling_enabled ? var.min_count : null
  max_count            = var.auto_scaling_enabled ? var.max_count : null
  node_count           = var.node_count

  temporary_name_for_rotation = "${substr(var.nodepool_name, 0, min(length(var.nodepool_name), 8))}tmp"

  priority        = var.spot ? "Spot" : "Regular"
  eviction_policy = var.spot ? "Delete" : null
  spot_max_price  = var.spot ? -1 : null

  zones       = var.zones
  node_taints = var.node_taints
  tags        = var.tags

  upgrade_settings {
    max_surge = "33%"
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

data "azapi_resource_list" "vmss_list" {
  type      = "Microsoft.Compute/virtualMachineScaleSets@2023-09-01"
  parent_id = "/subscriptions/${var.subscription_id}/resourceGroups/${data.azurerm_kubernetes_cluster.aks.node_resource_group}"

  depends_on = [azurerm_kubernetes_cluster_node_pool.automq]
}

locals {
  vmss_list = data.azapi_resource_list.vmss_list.output

  matched_vmss = [
    for vmss in local.vmss_list.value : vmss
    if try(vmss.tags["aks-managed-poolName"], "") == var.nodepool_name
  ]

  vmss_id = length(local.matched_vmss) > 0 ? local.matched_vmss[0].id : ""
}

resource "azapi_resource_action" "vmss_identity" {
  type        = "Microsoft.Compute/virtualMachineScaleSets@2023-09-01"
  resource_id = local.vmss_id
  action      = ""
  method      = "PATCH"

  body = {
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        (var.workload_identity_id) = {}
      }
    }
  }

  depends_on = [azurerm_kubernetes_cluster_node_pool.automq]

  lifecycle {
    precondition {
      condition     = local.vmss_id != ""
      error_message = "VMSS not found for node pool ${var.nodepool_name}. Ensure the node pool is created and tagged correctly."
    }
  }
}
