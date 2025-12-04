variable "location" {
  type        = string
  description = "Azure region"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "aks_name" {
  type        = string
  description = "AKS cluster name"
}

variable "kubernetes_version" {
  type        = string
  description = "AKS version"
  default     = null
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the default node pool"
}

variable "dns_prefix" {
  type        = string
  description = "DNS prefix for the cluster"
}

variable "kubeconfig_path" {
  type        = string
  description = "Local path to write kubeconfig file"
  default     = "~/.kube/automq-aks-config"
}

variable "identity_id" {
  type        = string
  description = "User assigned identity ID for AKS control plane"
}

variable "temporary_name_for_rotation" {
  type        = string
  description = "Temporary name used by AKS during node pool rotation"
  default     = "tmp"
}

variable "service_cidr" {
  type        = string
  description = "AKS service CIDR (must not overlap VNet/subnets)"
  default     = "10.2.0.0/16"
}

variable "dns_service_ip" {
  type        = string
  description = "IP for kube-dns within service CIDR"
  default     = "10.2.0.10"
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                         = "system"
    vm_size                      = "Standard_D4s_v3"
    node_count                   = 1
    vnet_subnet_id               = var.subnet_id
    only_critical_addons_enabled = true
    orchestrator_version         = var.kubernetes_version
    temporary_name_for_rotation  = var.temporary_name_for_rotation
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
  }

  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
}

# Ensure kubeconfig directory exists and write kubeconfig locally
resource "null_resource" "kubeconfig_dir" {
  provisioner "local-exec" {
    command = "mkdir -p $(dirname \"${var.kubeconfig_path}\")"
  }
}

resource "local_sensitive_file" "kubeconfig" {
  content  = azurerm_kubernetes_cluster.aks.kube_config_raw
  filename = var.kubeconfig_path

  depends_on = [null_resource.kubeconfig_dir]
}

output "kubernetes_cluster_id" {
  value = azurerm_kubernetes_cluster.aks.id
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "kube_config" {
  sensitive = true
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
}

output "kubernetes_version" {
  value = azurerm_kubernetes_cluster.aks.kubernetes_version
}

output "kubeconfig_path" {
  value = var.kubeconfig_path
}
