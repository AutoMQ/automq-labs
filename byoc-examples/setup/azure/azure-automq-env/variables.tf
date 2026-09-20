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

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be an Azure subscription UUID."
  }
}

variable "resource_group_name" {
  description = "Resource Group created for this quick-start"
  type        = string
}

variable "vnet_id" {
  description = "Existing VNet full ARM ID"
  type        = string

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+$", trimspace(var.vnet_id)))
    error_message = "vnet_id must be a full VNet ARM ID."
  }
}

variable "public_subnet_id" {
  description = "Existing subnet full ARM ID for the Console VM"
  type        = string
}

variable "private_subnet_id" {
  description = "Existing subnet full ARM ID for AKS nodes and load balancers"
  type        = string
}

variable "kubernetes_version" {
  description = "AKS control plane version"
  type        = string
  default     = "1.34.7"
}

variable "kubernetes_pricing_tier" {
  description = "AKS pricing tier"
  type        = string
  default     = "Free"
}

variable "service_cidr" {
  description = "Non-overlapping private CIDR for Kubernetes services"
  type        = string
}

variable "dns_service_ip" {
  description = "CoreDNS IP within service_cidr"
  type        = string
}

variable "name_prefix" {
  description = "Short lowercase prefix used for Azure resource names"
  type        = string
  default     = "automq"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,14}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 3-16 lowercase letters, numbers, or hyphens and cannot start or end with a hyphen."
  }
}

variable "nodepool" {
  description = "Dedicated AutoMQ AKS node pool"
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

variable "console_vm_size" {
  description = "Azure VM size for the AutoMQ Console"
  type        = string
  default     = "Standard_D2s_v5"
}

variable "console_allowed_cidr_blocks" {
  description = "IPv4 CIDRs allowed to access Console TCP 8080 and SSH TCP 22"
  type        = list(string)
  nullable    = false

  validation {
    condition = length(var.console_allowed_cidr_blocks) > 0 && length(var.console_allowed_cidr_blocks) < 1000 && alltrue([
      for cidr in var.console_allowed_cidr_blocks : can(cidrhost(cidr, 0)) && can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/", cidr))
    ])
    error_message = "console_allowed_cidr_blocks must contain 1-999 valid IPv4 CIDRs."
  }
}

variable "private_access_only" {
  description = "Disable public IPs for the AKS API server and Console VM"
  type        = bool
  default     = false
}
