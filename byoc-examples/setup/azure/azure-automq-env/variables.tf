variable "automq_config" {
  description = "Complete Base64-encoded AutoMQ BYOC CONFIG value from the Azure installation command"
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    condition = can(alltrue([
      for value in [
        jsondecode(base64decode(var.automq_config)).environmentId,
        jsondecode(base64decode(var.automq_config)).clientId,
        jsondecode(base64decode(var.automq_config)).clientSecret,
        jsondecode(base64decode(var.automq_config)).region,
        jsondecode(base64decode(var.automq_config)).opsBucket.bucketName,
      ] : trimspace(value) != ""
    ]))
    error_message = "automq_config must be valid Base64 JSON containing environmentId, clientId, clientSecret, region, and opsBucket.bucketName."
  }

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}:[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])?$", jsondecode(base64decode(var.automq_config)).opsBucket.bucketName))
    error_message = "CONFIG opsBucket.bucketName must use the Azure storageAccount:container format."
  }
}

variable "console_image" {
  description = "Exact AutoMQ Azure Console 8.x container image from the same installation command as CONFIG"
  type        = string
  nullable    = false

  validation {
    condition     = trimspace(var.console_image) != "" && !can(regex("[[:space:]]", var.console_image))
    error_message = "console_image must be a non-empty container image reference without whitespace."
  }
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name to create/use for all resources"
  type        = string
}

variable "vnet_id" {
  description = "Existing virtual network ID"
  type        = string
}

variable "public_subnet_id" {
  description = "Existing public subnet ID"
  type        = string
}

variable "private_subnet_id" {
  description = "Existing private subnet ID"
  type        = string
}

variable "kubernetes_version" {
  description = "AKS control plane version"
  type        = string
  default     = "1.34.7"
}

variable "kubernetes_pricing_tier" {
  type        = string
  description = "AKS pricing tier"
  default     = "Free"
}

variable "service_cidr" {
  description = "CIDR range for Kubernetes ClusterIP services; must be a private, non-overlapping range outside the AKS VNet and subnets."
  type        = string

}

variable "dns_service_ip" {
  description = "Cluster DNS service IP (CoreDNS) allocated from service_cidr; must be a single, unused IP within the service CIDR range."
  type        = string

}

variable "env_prefix" {
  description = "Short prefix used for naming resources"
  type        = string
}

variable "nodepool" {
  description = "Configuration for the AutoMQ user node pool"
  type = object({
    name       = string
    vm_size    = string
    min_count  = number
    max_count  = number
    node_count = number
    spot       = bool
  })
  default = {
    name       = "automq"
    vm_size    = "Standard_D4as_v5"
    min_count  = 3
    max_count  = 20
    node_count = 3
    spot       = false
  }
}

variable "automq_console_vm_size" {
  description = "VM size for AutoMQ console"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "private_access_only" {
  description = "If true, the AKS API server and AutoMQ console will not have public IPs. Access will be restricted to the VNet."
  type        = bool
  default     = false
}

variable "kubernetes_namespace" {
  description = "Optional Kubernetes namespace for the AutoMQ workload identity federation subject"
  type        = string
  default     = ""
}

variable "kubernetes_service_account" {
  description = "Optional Kubernetes ServiceAccount for the AutoMQ workload identity federation subject"
  type        = string
  default     = ""
}
