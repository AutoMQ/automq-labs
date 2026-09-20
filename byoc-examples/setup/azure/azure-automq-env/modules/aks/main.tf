variable "location" {
  type        = string
  description = "Azure region"
}

variable "resource_group_name" {
  type        = string
  description = "Resource Group name"
}

variable "aks_name" {
  type        = string
  description = "AKS cluster name"
}

variable "kubernetes_version" {
  type        = string
  description = "AKS version"
}

variable "subnet_id" {
  type        = string
  description = "AKS subnet full ARM ID"
}

variable "dns_prefix" {
  type        = string
  description = "AKS DNS prefix"
}

variable "service_cidr" {
  type        = string
  description = "Kubernetes service CIDR"
}

variable "dns_service_ip" {
  type        = string
  description = "Kubernetes DNS service IP"
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "kubernetes_pricing_tier" {
  type        = string
  description = "AKS pricing tier"
}

variable "private_access_only" {
  type        = bool
  description = "Enable a private AKS API server"
}

variable "availability_zones" {
  type        = list(string)
  description = "Azure availability zones used by the system node pool"
}

data "azurerm_client_config" "current" {}

resource "azurerm_user_assigned_identity" "aks" {
  name                = "uai-aks-${var.aks_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_role_assignment" "aks_network_contributor" {
  role_definition_name = "Network Contributor"
  scope                = "/subscriptions/${var.subscription_id}"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_role_assignment" "aks_contributor" {
  role_definition_name = "Contributor"
  scope                = "/subscriptions/${var.subscription_id}"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.aks_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.kubernetes_pricing_tier

  private_cluster_enabled           = var.private_access_only
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = "Standard_D4s_v3"
    node_count                   = 1
    vnet_subnet_id               = var.subnet_id
    only_critical_addons_enabled = true
    orchestrator_version         = var.kubernetes_version
    temporary_name_for_rotation  = "systmp"
    zones                        = var.availability_zones
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
  }

  depends_on = [
    azurerm_role_assignment.aks_contributor,
    azurerm_role_assignment.aks_network_contributor,
  ]
}

output "kubernetes_cluster_id" {
  value = azurerm_kubernetes_cluster.this.id
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "kubernetes_version" {
  value = azurerm_kubernetes_cluster.this.kubernetes_version
}
