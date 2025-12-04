variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
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
  default     = null
}

variable "service_cidr" {
  description = "AKS service CIDR (must not overlap VNet/subnets)"
  type        = string
  default     = "10.2.0.0/16"
}

variable "dns_service_ip" {
  description = "DNS service IP inside service CIDR"
  type        = string
  default     = "10.2.0.10"
}

variable "kubeconfig_path" {
  description = "Local path to write kubeconfig file"
  type        = string
  default     = "~/.kube/automq-aks-config"
}

variable "temporary_name_for_rotation" {
  description = "Temporary name used by AKS for node pool rotation"
  type        = string
  default     = "tmp"
}

variable "env_prefix" {
  description = "Short prefix used for naming resources"
  type        = string
  default     = "automq"
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
    min_count  = 1
    max_count  = 5
    node_count = 2
    spot       = false
  }
}

variable "ops_storage_account_name" {
  description = "Existing storage account name for operations bucket"
  type        = string
}

variable "ops_storage_resource_group" {
  description = "Resource group name for the ops storage account"
  type        = string
}

variable "ops_container_name" {
  description = "Existing container name in the ops storage account"
  type        = string
}

variable "data_storage_account_name" {
  description = "Existing storage account name for data bucket"
  type        = string
}

variable "data_storage_resource_group" {
  description = "Resource group name for the data storage account"
  type        = string
}

variable "data_container_name" {
  description = "Existing container name in the data storage account"
  type        = string
}

variable "automq_console_id" {
  description = "Image ID for AutoMQ console VM"
  type        = string
  default     = "/subscriptions/218357d0-eaaf-4e3e-9ffa-6b4ccb7e2df9/resourceGroups/automq-image/providers/Microsoft.Compute/images/AutoMQ-control-center-Prod-7.8.7-x86_64"
}

variable "automq_console_vm_size" {
  description = "VM size for AutoMQ console"
  type        = string
  default     = "Standard_D2s_v3"
}
