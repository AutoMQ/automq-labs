variable "location" {
  type        = string
  description = "Azure region"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group where resources are created"
}

variable "vnet_id" {
  type        = string
  description = "ID of the virtual network"
}

variable "public_subnet_id" {
  type        = string
  description = "Subnet ID for the console VM (public)"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs associated with the VNet"
}

variable "ops_storage_account_name" {
  type        = string
  description = "Existing storage account name for ops bucket"
}

variable "ops_storage_resource_group" {
  type        = string
  description = "Resource group name for the ops storage account"
}

variable "ops_container_name" {
  type        = string
  description = "Existing container name for ops bucket"
}

variable "data_storage_account_name" {
  type        = string
  description = "Existing storage account name for data bucket"
}

variable "data_storage_resource_group" {
  type        = string
  description = "Resource group name for the data storage account"
}

variable "data_container_name" {
  type        = string
  description = "Existing container name for data bucket"
}

variable "image_id" {
  type        = string
  description = "Custom image ID for the CMP console VM"
}

variable "vm_size" {
  type        = string
  description = "VM size for the CMP console"
}

variable "cluster_identity_id" {
  type        = string
  description = "User-assigned identity ID used by the cluster and console"
}

locals {
  env_name              = "automq-console"
  vm_admin_username     = "azureuser"
  ssh_algorithm         = "RSA"
  ssh_bits              = 4096
  dns_zone_name         = "automq-console.automq.private"
  dns_link_name         = "automq-console-vnet-link"
  storage_account_scope = "/subscriptions/${split("/", var.vnet_id)[2]}/resourceGroups/${split("/", var.vnet_id)[4]}"
  ssh_private_key_path  = "${pathexpand("~/.ssh")}/${"${local.env_name}-ssh-key"}.pem"
}

# SSH key for console access
resource "tls_private_key" "ssh" {
  algorithm = local.ssh_algorithm
  rsa_bits  = local.ssh_bits
}

resource "local_file" "ssh_private_key" {
  filename        = local.ssh_private_key_path
  file_permission = "0600"
  content         = tls_private_key.ssh.private_key_pem
}

# Identities
resource "azurerm_user_assigned_identity" "console" {
  name                = "uai-${local.env_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
}

# DNS zone for internal records
resource "azurerm_private_dns_zone" "zone" {
  name                = local.dns_zone_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "zone_link" {
  name                  = local.dns_link_name
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.zone.name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
}

# Public IP and NIC for console
resource "azurerm_public_ip" "console" {
  name                = "pip-${local.env_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "console" {
  name                = "nsg-${local.env_name}"
  resource_group_name = var.resource_group_name
  location            = var.location

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP-8080"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "console" {
  name                = "nic-${local.env_name}"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.public_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.console.id
  }
}

resource "azurerm_network_interface_security_group_association" "console" {
  network_interface_id      = azurerm_network_interface.console.id
  network_security_group_id = azurerm_network_security_group.console.id
}

# Reference existing storage accounts
data "azurerm_storage_account" "ops" {
  name                = var.ops_storage_account_name
  resource_group_name = var.ops_storage_resource_group
}

data "azurerm_storage_account" "data" {
  name                = var.data_storage_account_name
  resource_group_name = var.data_storage_resource_group
}

resource "azurerm_linux_virtual_machine" "console" {
  name                  = "vm-${local.env_name}"
  resource_group_name   = var.resource_group_name
  location              = var.location
  size                  = var.vm_size
  admin_username        = local.vm_admin_username
  network_interface_ids = [azurerm_network_interface.console.id]

  admin_ssh_key {
    username   = local.vm_admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.console.id, var.cluster_identity_id]
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_id = var.image_id

  custom_data = base64encode(templatefile("${path.module}/init.sh", {
    managedIdentityClientId   = azurerm_user_assigned_identity.console.client_id
    opsContainerName          = var.ops_container_name
    opsStorageAccountEndpoint = data.azurerm_storage_account.ops.primary_blob_endpoint
    uniqueId                  = local.env_name
    vpcName                   = split("/", var.vnet_id)[8]
    vpcResourceGroupName      = split("/", var.vnet_id)[4]
  }))
}

output "console_endpoint" {
  value = "http://${azurerm_public_ip.console.ip_address}:8080"
}

output "console_initial_username" {
  value = "admin"
}

output "console_initial_password" {
  value = azurerm_linux_virtual_machine.console.id
}

output "console_role_id" {
  value = azurerm_user_assigned_identity.console.client_id
}

output "console_role_arn" {
  value = azurerm_user_assigned_identity.console.id
}
