variable "location" {
  type        = string
  description = "Azure region"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "name_suffix" {
  type        = string
  description = "Suffix to make resource names unique"
}

variable "vnet_cidr" {
  type        = string
  description = "CIDR for the VNet (e.g., 10.0.0.0/16)"
  default     = "10.0.0.0/16"
}

# Virtual Network for OpenShift cluster
resource "azurerm_virtual_network" "openshift" {
  name                = "vnet-${var.name_suffix}"
  address_space       = [var.vnet_cidr]
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = {
    purpose = "AutoMQ OpenShift Infrastructure"
  }
}

# Master subnet for OpenShift control plane
# ARO requirements: /27 minimum (32 IPs), no NSG, no UDR
resource "azurerm_subnet" "master" {
  name                 = "snet-master-${var.name_suffix}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.openshift.name
  # Use first /27 subnet from VNet (e.g., 10.0.0.0/27 for 10.0.0.0/16)
  # This provides 32 IPs, meeting ARO minimum requirement
  address_prefixes = [cidrsubnet(var.vnet_cidr, 11, 0)]

  # Service endpoints for Azure services
  service_endpoints = ["Microsoft.Storage", "Microsoft.ContainerRegistry"]
}

# Worker subnet for OpenShift worker nodes
# ARO requirements: /27 minimum, no NSG, no UDR
resource "azurerm_subnet" "worker" {
  name                 = "snet-worker-${var.name_suffix}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.openshift.name
  # Use /24 (256 IPs) for worker subnet to accommodate more nodes
  # This is split from the VNet: cidrsubnet(10.0.0.0/16, 8, 1) = 10.0.1.0/24
  address_prefixes = [cidrsubnet(var.vnet_cidr, 8, 1)]

  # Service endpoints for Azure services
  service_endpoints = ["Microsoft.Storage", "Microsoft.ContainerRegistry"]
}

output "vnet_id" {
  description = "Virtual Network ID for OpenShift cluster"
  value       = azurerm_virtual_network.openshift.id
}

output "vnet_name" {
  description = "Virtual Network name"
  value       = azurerm_virtual_network.openshift.name
}

output "master_subnet_id" {
  description = "Master subnet ID for OpenShift control plane"
  value       = azurerm_subnet.master.id
}

output "worker_subnet_id" {
  description = "Worker subnet ID for OpenShift worker nodes"
  value       = azurerm_subnet.worker.id
}

