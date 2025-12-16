variable "kubernetes_cluster_id" {
  type        = string
  description = "ID of the AKS cluster"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the node pool"
}

variable "nodepool_name" {
  type        = string
  description = "Name of the AutoMQ node pool"

  validation {
    condition     = length(var.nodepool_name) <= 12 && can(regex("^[a-z0-9]+$", var.nodepool_name))
    error_message = "nodepool_name must be 1-12 lowercase alphanumeric characters (AKS agent pool naming constraint)."
  }
}

variable "vm_size" {
  type        = string
  description = "VM size for nodes"
}

variable "min_count" {
  type        = number
  description = "Minimum node count"
}

variable "max_count" {
  type        = number
  description = "Maximum node count"
}

variable "node_count" {
  type        = number
  description = "Initial node count"
}

variable "spot" {
  type        = bool
  description = "Use spot nodes"
  default     = false
}

variable "orchestrator_version" {
  type        = string
  description = "Kubernetes version to align with the cluster"
  default     = null
}

variable "cluster_identity_id" {
  type        = string
  description = "User-assigned identity resource ID to attach to the node pool VMSS"
  default     = ""
}

resource "azurerm_kubernetes_cluster_node_pool" "automq" {
  name                  = var.nodepool_name
  kubernetes_cluster_id = var.kubernetes_cluster_id
  vm_size               = var.vm_size
  vnet_subnet_id        = var.subnet_id

  orchestrator_version = var.orchestrator_version

  auto_scaling_enabled = true
  min_count            = var.min_count
  max_count            = var.max_count
  node_count           = var.node_count

  temporary_name_for_rotation = "automqtmp"

  priority        = var.spot ? "Spot" : "Regular"
  eviction_policy = var.spot ? "Delete" : null
  spot_max_price  = var.spot ? -1 : null

  zones = [1, 2, 3]

  node_taints = ["dedicated=automq:NoSchedule"]

  upgrade_settings {
    max_surge = "33%"
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

# Get AKS cluster info to retrieve node resource group
data "azurerm_kubernetes_cluster" "aks" {
  name                = regex("/managedClusters/([^/]+)$", var.kubernetes_cluster_id)[0]
  resource_group_name = regex("/resourceGroups/([^/]+)/", var.kubernetes_cluster_id)[0]

  depends_on = [azurerm_kubernetes_cluster_node_pool.automq]
}

# List all VMSS in the node resource group
data "azapi_resource_list" "vmss_list" {
  type      = "Microsoft.Compute/virtualMachineScaleSets@2023-09-01"
  parent_id = "/subscriptions/${regex("/subscriptions/([^/]+)/", var.kubernetes_cluster_id)[0]}/resourceGroups/${data.azurerm_kubernetes_cluster.aks.node_resource_group}"

  depends_on = [azurerm_kubernetes_cluster_node_pool.automq]
}

# Find the VMSS matching the node pool name by tag
locals {
  # output is already decoded as an object
  vmss_list = data.azapi_resource_list.vmss_list.output
  
  # Filter VMSS by aks-managed-poolName tag
  matched_vmss = [
    for vmss in local.vmss_list.value : vmss
    if try(vmss.tags["aks-managed-poolName"], "") == var.nodepool_name
  ]
  
  vmss_id = length(local.matched_vmss) > 0 ? local.matched_vmss[0].id : ""
}

# Assign user-assigned identity to the VMSS using azapi_resource_action
# Using PATCH method to avoid cross-subscription validation issues
resource "azapi_resource_action" "vmss_identity" {
  type        = "Microsoft.Compute/virtualMachineScaleSets@2023-09-01"
  resource_id = local.vmss_id
  action      = ""
  method      = "PATCH"

  body = {
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        (var.cluster_identity_id) = {}
      }
    }
  }

  depends_on = [azurerm_kubernetes_cluster_node_pool.automq]
  
  lifecycle {
    precondition {
      condition     = local.vmss_id != ""
      error_message = "VMSS not found for node pool ${var.nodepool_name}. Ensure the node pool is created and tagged correctly."
    }
    precondition {
      condition     = var.cluster_identity_id != ""
      error_message = "cluster_identity_id must be provided to assign identity to the VMSS."
    }
  }
}

output "nodepool_name" {
  value = azurerm_kubernetes_cluster_node_pool.automq.name
}
