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

  priority        = var.spot ? "Spot" : "Regular"
  eviction_policy = var.spot ? "Delete" : null
  spot_max_price  = var.spot ? -1 : null

  node_taints = ["dedicated=automq:NoSchedule"]

  upgrade_settings {
    max_surge = "33%"
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

# Assign user-assigned identity to the underlying VMSS after node pool creation (if provided)
resource "null_resource" "vmss_identity" {
  triggers = {
    node_pool_id     = azurerm_kubernetes_cluster_node_pool.automq.id
    cluster_identity = var.cluster_identity_id
  }

  provisioner "local-exec" {
    when        = create
    command     = <<-EOT
      set -euo pipefail
      if [ -z "${var.cluster_identity_id}" ]; then
        echo "cluster_identity_id is empty, skip VMSS identity assignment"
        exit 0
      fi

      CLUSTER_ID="${azurerm_kubernetes_cluster_node_pool.automq.kubernetes_cluster_id}"
      CLUSTER_RG=$(echo "$CLUSTER_ID" | awk -F'/' '{print $5}')
      CLUSTER_NAME=$(echo "$CLUSTER_ID" | awk -F'/' '{print $9}')

      NODE_RG=$(az aks show --resource-group "$CLUSTER_RG" --name "$CLUSTER_NAME" --query nodeResourceGroup -o tsv)
      VMSS_NAME=$(az vmss list -g "$NODE_RG" -o json | jq -r '.[] | select(.tags["aks-managed-poolName"]=="${azurerm_kubernetes_cluster_node_pool.automq.name}").name')

      echo "Assigning identity ${var.cluster_identity_id} to VMSS $${VMSS_NAME} in $${NODE_RG}"
      az vmss identity assign -g "$NODE_RG" -n "$VMSS_NAME" --identities "${var.cluster_identity_id}" 1>/dev/null
      echo "Identity assigned."
    EOT
    interpreter = ["bash", "-c"]
  }
}

output "nodepool_name" {
  value = azurerm_kubernetes_cluster_node_pool.automq.name
}
