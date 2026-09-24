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

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the console VM (private)"
}



variable "ops_container_name" {
  type        = string
  description = "Existing container name for ops bucket"
}

variable "data_container_name" {
  type        = string
  description = "Existing container name for data bucket"
}

variable "automq_config" {
  type        = string
  description = "Complete Base64-encoded AutoMQ BYOC CONFIG value"
  sensitive   = true
}

variable "console_image" {
  type        = string
  description = "AutoMQ Azure Console 8.x container image"
}

variable "vm_size" {
  type        = string
  description = "VM size for the CMP console"
}

variable "kubernetes_cluster_id" {
  type        = string
  description = "AKS cluster full ARM ID"
}

variable "subscription_id" {
  type        = string
  description = "Subscription ID for role assignments"
}

variable "storage_account_name" {
  type        = string
  description = "The name of the storage account."
}

variable "private_access_only" {
  description = "If true, the console will not have a public IP."
  type        = bool
  default     = false
}

resource "random_password" "initial_password" {
  length  = 24
  special = false
}

locals {
  env_name                  = "automq-console"
  vm_admin_username         = "azureuser"
  ssh_algorithm             = "RSA"
  ssh_bits                  = 4096
  dns_zone_name             = "automq-console.automq.private"
  dns_link_name             = "automq-console-vnet-link"
  storage_account_scope     = "/subscriptions/${split("/", var.vnet_id)[2]}/resourceGroups/${split("/", var.vnet_id)[4]}"
  ssh_private_key_path      = pathexpand("~/.ssh/${local.env_name}-ssh-key.pem")
  data_disk_name            = "${local.env_name}-datadisk"
  disk_size_gb              = 20
  disk_storage_account_type = "Premium_LRS"
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
  name                 = local.dns_link_name
  private_dns_zone_id  = azurerm_private_dns_zone.zone.id
  virtual_network_id   = var.vnet_id
  registration_enabled = false
}

# Public IP and NIC for console
resource "azurerm_public_ip" "console" {
  count               = var.private_access_only ? 0 : 1
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
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.private_access_only ? null : azurerm_public_ip.console[0].id
  }
}

resource "azurerm_network_interface_security_group_association" "console" {
  network_interface_id      = azurerm_network_interface.console.id
  network_security_group_id = azurerm_network_security_group.console.id
}

resource "azurerm_storage_account" "storage" {
  name                     = var.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_container" "automq_data" {
  name                  = var.data_container_name
  storage_account_id    = azurerm_storage_account.storage.id
  container_access_type = "private"
  metadata              = { automqvendor = "automq" }
}

resource "azurerm_storage_container" "automq_ops" {
  name                  = var.ops_container_name
  storage_account_id    = azurerm_storage_account.storage.id
  container_access_type = "private"
  metadata              = { automqvendor = "automq" }
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
    identity_ids = [azurerm_user_assigned_identity.console.id]
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/userdata.tftpl", {
    automq_config_b64    = base64encode(var.automq_config)
    console_image_b64    = base64encode(var.console_image)
    initial_password_b64 = base64encode(random_password.initial_password.result)
  }))

  depends_on = [
    azurerm_role_assignment.console_managed_dns,
    azurerm_role_assignment.console_managed_dns_vnet,
    azurerm_role_assignment.console_managed_rbac_delegation,
    azurerm_role_assignment.console_managed_storage,
    azurerm_role_assignment.console_managed_target_blob_data,
    azurerm_role_assignment.console_managed_uami,
    azurerm_role_assignment.console_required_aks_access,
    azurerm_role_assignment.console_required_aks_cluster_admin,
    azurerm_role_assignment.console_required_blob_data,
    azurerm_role_assignment.console_required_dns_records,
    azurerm_role_assignment.console_required_read,
  ]
}


resource "azurerm_managed_disk" "data_disk" {
  name                 = local.data_disk_name
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = local.disk_storage_account_type
  create_option        = "Empty"
  disk_size_gb         = local.disk_size_gb
}

resource "azurerm_virtual_machine_data_disk_attachment" "data_disk_attachment" {
  managed_disk_id    = azurerm_managed_disk.data_disk.id
  virtual_machine_id = azurerm_linux_virtual_machine.console.id
  lun                = 10
  caching            = "ReadWrite"
}


output "console_endpoint" {
  value = var.private_access_only ? "http://${azurerm_network_interface.console.private_ip_address}:8080" : "http://${azurerm_public_ip.console[0].ip_address}:8080"
}

output "console_initial_username" {
  value = "admin"
}

output "console_initial_password" {
  value     = random_password.initial_password.result
  sensitive = true
}

output "console_role_id" {
  value = azurerm_user_assigned_identity.console.client_id
}

output "console_role_arn" {
  value = azurerm_user_assigned_identity.console.id
}

output "dns_zone_name" {
  value = azurerm_private_dns_zone.zone.name
}

output "dns_zone_id" {
  value = azurerm_private_dns_zone.zone.id
}

output "data_bucket_name" {
  # Blob container name supplied by user
  value = var.data_container_name
}

output "data_bucket_endpoint" {
  value = azurerm_storage_account.storage.primary_blob_endpoint
}

output "ops_storage_container_id" {
  value = azurerm_storage_container.automq_ops.id
}

output "data_storage_container_id" {
  value = azurerm_storage_container.automq_data.id
}
