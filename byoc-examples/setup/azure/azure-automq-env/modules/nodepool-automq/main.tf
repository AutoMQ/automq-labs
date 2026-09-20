variable "kubernetes_cluster_id" {
  type        = string
  description = "AKS cluster full ARM ID"
}

variable "subnet_id" {
  type        = string
  description = "AKS node subnet full ARM ID"
}

variable "nodepool_name" {
  type        = string
  description = "AutoMQ node pool name"

  validation {
    condition     = length(var.nodepool_name) <= 12 && can(regex("^[a-z0-9]+$", var.nodepool_name))
    error_message = "nodepool_name must be 1-12 lowercase alphanumeric characters."
  }
}

variable "vm_size" {
  type        = string
  description = "Azure VM size for nodes"
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
  description = "Use Spot nodes"
}

variable "orchestrator_version" {
  type        = string
  description = "Kubernetes version aligned with the cluster"
}

variable "availability_zones" {
  type        = list(string)
  description = "Azure availability zones used by this node pool"
}

resource "azurerm_kubernetes_cluster_node_pool" "automq" {
  name                  = var.nodepool_name
  kubernetes_cluster_id = var.kubernetes_cluster_id
  vm_size               = var.vm_size
  vnet_subnet_id        = var.subnet_id
  orchestrator_version  = var.orchestrator_version

  auto_scaling_enabled = true
  min_count            = var.min_count
  max_count            = var.max_count
  node_count           = var.node_count

  temporary_name_for_rotation = "automqtmp"
  priority                    = var.spot ? "Spot" : "Regular"
  eviction_policy             = var.spot ? "Delete" : null
  spot_max_price              = var.spot ? -1 : null
  zones                       = var.availability_zones
  node_taints                 = ["dedicated=automq:NoSchedule"]
  node_labels                 = { automq-node-group = var.nodepool_name }

  upgrade_settings {
    max_surge = "33%"
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

output "nodepool_name" {
  value = azurerm_kubernetes_cluster_node_pool.automq.name
}

output "vm_size" {
  value = azurerm_kubernetes_cluster_node_pool.automq.vm_size
}
