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
  default     = "1.32.9"
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

variable "kubeconfig_path" {
  description = "Local path to write kubeconfig file"
  type        = string
  default     = "~/.kube/automq-aks-config"
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

variable "automq_console_id" {
  description = "Image ID for AutoMQ console VM"
  type        = string
  default     = "/communityGalleries/automqimages-7a9bb1ec-7a2b-44cd-a3ae-a797cc8dd7eb/images/automq-control-center-gen1/versions/7.8.11"
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
