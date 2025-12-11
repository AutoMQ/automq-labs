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

variable "env_prefix" {
  description = "Short prefix used for naming resources"
  type        = string
}

variable "storage_account_tier" {
  description = "Storage account tier (Standard or Premium)"
  type        = string
  default     = "Standard"
}

variable "storage_account_replication_type" {
  description = "Storage account replication type (LRS, GRS, RAGRS, ZRS)"
  type        = string
  default     = "LRS"
}

variable "vnet_cidr" {
  description = "CIDR block for the Virtual Network (e.g., 10.0.0.0/16)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "openshift_cluster_name" {
  description = "Name of the Azure Red Hat OpenShift cluster"
  type        = string
  default     = null
}

variable "openshift_version" {
  description = "OpenShift version in X.Y.Z format (e.g., 4.18.26). Defaults to 4.18.26 if not specified"
  type        = string
  default     = null
}

variable "master_vm_size" {
  description = "VM size for OpenShift master nodes. Common options: Standard_D8s_v3 (recommended), Standard_D8s_v5, Standard_D4s_v3"
  type        = string
  default     = "Standard_D8s_v3" # v3 series typically has better availability
}

variable "worker_vm_size" {
  description = "VM size for OpenShift worker nodes. Common options: Standard_D4s_v3 (recommended), Standard_D4s_v5, Standard_D8s_v3"
  type        = string
  default     = "Standard_D4s_v3" # v3 series typically has better availability
}

variable "worker_node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3
}

variable "create_openshift_cluster" {
  description = "Whether to create the OpenShift cluster (set to false to only create infrastructure)"
  type        = bool
  default     = true
}

# Additional Node Pool Configuration
variable "create_automq_node_pool" {
  description = "Whether to create a dedicated node pool for AutoMQ workloads"
  type        = bool
  default     = false
}

variable "automq_node_pool_count" {
  description = "Number of nodes in the AutoMQ dedicated node pool"
  type        = number
  default     = 3
}

variable "automq_node_pool_vm_size" {
  description = "VM size for AutoMQ dedicated node pool. Common options: Standard_D4s_v3 (recommended), Standard_D4s_v5"
  type        = string
  default     = "Standard_D4s_v3" # v3 series typically has better availability
}

# Service Principal for OpenShift Cluster
# If not provided, Terraform will automatically create one
variable "service_principal_client_id" {
  description = "Service Principal Client ID for OpenShift cluster. If not provided, Terraform will create one automatically."
  type        = string
  default     = null
  sensitive   = true
}

variable "service_principal_client_secret" {
  description = "Service Principal Client Secret for OpenShift cluster. If not provided, Terraform will create one automatically."
  type        = string
  default     = null
  sensitive   = true
}
