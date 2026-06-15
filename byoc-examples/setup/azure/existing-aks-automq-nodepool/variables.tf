variable "subscription_id" {
  type        = string
  description = "Azure subscription ID."
}

variable "aks_name" {
  type        = string
  description = "Name of the existing AKS cluster."
}

variable "aks_resource_group_name" {
  type        = string
  description = "Resource group name of the existing AKS cluster."
}

variable "nodepool_name" {
  type        = string
  description = "Name of the AutoMQ node pool to create."

  validation {
    condition     = length(var.nodepool_name) >= 1 && length(var.nodepool_name) <= 12 && can(regex("^[a-z0-9]+$", var.nodepool_name))
    error_message = "nodepool_name must be 1-12 lowercase alphanumeric characters."
  }
}

variable "workload_identity_id" {
  type        = string
  description = "User-assigned managed identity resource ID to attach to the AutoMQ node pool VMSS."

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.managedidentity/userassignedidentities/[^/]+$", var.workload_identity_id))
    error_message = "workload_identity_id must be a full Azure user-assigned managed identity resource ID."
  }
}

variable "subnet_id" {
  type        = string
  description = "Subnet resource ID for the AutoMQ node pool."
}

variable "vm_size" {
  type        = string
  description = "VM size for AutoMQ nodes."
}

variable "node_count" {
  type        = number
  description = "Initial node count."
  default     = 3
}

variable "min_count" {
  type        = number
  description = "Minimum node count when autoscaling is enabled."
  default     = 3
}

variable "max_count" {
  type        = number
  description = "Maximum node count when autoscaling is enabled."
  default     = 20
}

variable "auto_scaling_enabled" {
  type        = bool
  description = "Whether to enable cluster autoscaler for the AutoMQ node pool."
  default     = true
}

variable "spot" {
  type        = bool
  description = "Whether to use Spot nodes."
  default     = false
}

variable "orchestrator_version" {
  type        = string
  description = "Kubernetes version for the node pool. Defaults to the existing cluster version."
  default     = null
}

variable "zones" {
  type        = list(string)
  description = "Availability zones for the AutoMQ node pool."
  default     = ["1", "2", "3"]
}

variable "node_taints" {
  type        = list(string)
  description = "Kubernetes taints applied to the AutoMQ node pool."
  default     = ["dedicated=automq:NoSchedule"]
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the AutoMQ node pool cloud resources."
  default     = {}
}
