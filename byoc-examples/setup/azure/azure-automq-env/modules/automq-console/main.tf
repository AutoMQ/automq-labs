variable "location" {
  type        = string
  description = "Azure region"
}

variable "resource_group_name" {
  type        = string
  description = "Resource Group where Console resources are created"
}

variable "vnet_id" {
  type        = string
  description = "Existing VNet full ARM ID"
}

variable "subnet_id" {
  type        = string
  description = "Existing Console subnet full ARM ID"
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
  description = "Azure VM size for the Console"
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "ops_bucket_id" {
  type        = string
  description = "Canonical Azure logical Ops Bucket ID in storageAccount:container form"
}

variable "kubernetes_cluster_id" {
  type        = string
  description = "AKS cluster full ARM ID"
}

variable "console_allowed_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDRs allowed to access the Console and SSH"
}

variable "private_access_only" {
  description = "Disable the Console public IP"
  type        = bool
  default     = false
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "random_password" "initial_password" {
  length  = 24
  special = false
}

resource "random_password" "initial_access_key" {
  length  = 16
  special = false
}

resource "random_password" "initial_secret_key" {
  length  = 32
  special = false
}

locals {
  automq_config             = jsondecode(base64decode(var.automq_config))
  environment_slug          = substr(replace(lower(nonsensitive(local.automq_config.environmentId)), "/[^a-z0-9]/", ""), 0, 12)
  name_suffix               = "${local.environment_slug}${random_string.suffix.result}"
  vm_admin_username         = "automq"
  ops_bucket_parts          = split(":", var.ops_bucket_id)
  ops_storage_account_name  = local.ops_bucket_parts[0]
  ops_container_name        = local.ops_bucket_parts[1]
  data_storage_account_name = substr("amqdata${local.name_suffix}", 0, 24)
  data_container_name       = "data"
  data_bucket_id            = "${local.data_storage_account_name}:${local.data_container_name}"
  dns_zone_name             = "${local.name_suffix}.automq.private"
  ssh_private_key_path      = pathexpand("~/.ssh/automq-console-${local.name_suffix}.pem")
  subscription_scope        = "/subscriptions/${var.subscription_id}"
  allowed_cidrs             = { for index, cidr in var.console_allowed_cidr_blocks : tostring(index) => cidr }
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "ssh_private_key" {
  filename        = local.ssh_private_key_path
  file_permission = "0600"
  content         = tls_private_key.ssh.private_key_pem
}

resource "azurerm_user_assigned_identity" "console" {
  name                = "uai-automq-console-${local.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_user_assigned_identity" "workload" {
  name                = "uai-automq-workload-${local.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
}

# Evaluation-friendly permissions. Review and narrow these grants before using
# the example as a production baseline.
resource "azurerm_role_assignment" "console_contributor" {
  role_definition_name = "Contributor"
  scope                = local.subscription_scope
  principal_id         = azurerm_user_assigned_identity.console.principal_id
}

resource "azurerm_role_assignment" "console_rbac_admin" {
  role_definition_name = "Role Based Access Control Administrator"
  scope                = local.subscription_scope
  principal_id         = azurerm_user_assigned_identity.console.principal_id
}

resource "azurerm_role_assignment" "console_aks_user" {
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  scope                = var.kubernetes_cluster_id
  principal_id         = azurerm_user_assigned_identity.console.principal_id
}

resource "azurerm_role_assignment" "console_aks_rbac_admin" {
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  scope                = var.kubernetes_cluster_id
  principal_id         = azurerm_user_assigned_identity.console.principal_id
}

resource "azurerm_public_ip" "console" {
  count = var.private_access_only ? 0 : 1

  name                = "pip-automq-console-${local.name_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "console" {
  name                = "nsg-automq-console-${local.name_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_network_security_rule" "console" {
  for_each = local.allowed_cidrs

  name                        = "Console-${each.key}"
  priority                    = 1000 + tonumber(each.key)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8080"
  source_address_prefix       = each.value
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.console.name
}

resource "azurerm_network_security_rule" "ssh" {
  for_each = local.allowed_cidrs

  name                        = "SSH-${each.key}"
  priority                    = 2000 + tonumber(each.key)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = each.value
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.console.name
}

resource "azurerm_network_interface" "console" {
  name                = "nic-automq-console-${local.name_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.private_access_only ? null : azurerm_public_ip.console[0].id
  }
}

resource "azurerm_network_interface_security_group_association" "console" {
  network_interface_id      = azurerm_network_interface.console.id
  network_security_group_id = azurerm_network_security_group.console.id
}

resource "azurerm_storage_account" "ops" {
  name                     = local.ops_storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}

resource "azurerm_storage_container" "ops" {
  name                  = local.ops_container_name
  storage_account_id    = azurerm_storage_account.ops.id
  container_access_type = "private"
}

resource "azurerm_storage_account" "data" {
  name                     = local.data_storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}

resource "azurerm_storage_container" "data" {
  name                  = local.data_container_name
  storage_account_id    = azurerm_storage_account.data.id
  container_access_type = "private"
}

resource "azurerm_private_dns_zone" "this" {
  name                = local.dns_zone_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  name                  = "automq-vnet-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
}

resource "azurerm_role_assignment" "console_ops_blob" {
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_container.ops.id
  principal_id         = azurerm_user_assigned_identity.console.principal_id
}

resource "azurerm_role_assignment" "workload_ops_blob" {
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_container.ops.id
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

resource "azurerm_role_assignment" "workload_data_blob" {
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_container.data.id
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

resource "azurerm_role_assignment" "workload_dns" {
  role_definition_name = "Private DNS Zone Contributor"
  scope                = azurerm_private_dns_zone.this.id
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

resource "azurerm_managed_disk" "console_data" {
  name                 = "disk-automq-console-${local.name_suffix}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 20
}

resource "azurerm_linux_virtual_machine" "console" {
  name                  = "vm-automq-console-${local.name_suffix}"
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
    automq_config_b64      = base64encode(var.automq_config)
    console_image_b64      = base64encode(var.console_image)
    initial_password_b64   = base64encode(random_password.initial_password.result)
    initial_access_key_b64 = base64encode(random_password.initial_access_key.result)
    initial_secret_key_b64 = base64encode(random_password.initial_secret_key.result)
  }))

  depends_on = [
    azurerm_role_assignment.console_aks_rbac_admin,
    azurerm_role_assignment.console_aks_user,
    azurerm_role_assignment.console_contributor,
    azurerm_role_assignment.console_ops_blob,
    azurerm_role_assignment.console_rbac_admin,
  ]
}

resource "azurerm_virtual_machine_data_disk_attachment" "console_data" {
  managed_disk_id    = azurerm_managed_disk.console_data.id
  virtual_machine_id = azurerm_linux_virtual_machine.console.id
  lun                = 10
  caching            = "ReadWrite"
}

output "console_endpoint" {
  value = var.private_access_only ? "http://${azurerm_network_interface.console.private_ip_address}:8080" : "http://${azurerm_public_ip.console[0].ip_address}:8080"
}

output "console_initial_password" {
  value     = random_password.initial_password.result
  sensitive = true
}

output "console_initial_access_key" {
  value     = random_password.initial_access_key.result
  sensitive = true
}

output "console_initial_secret_key" {
  value     = random_password.initial_secret_key.result
  sensitive = true
}

output "console_vm_id" {
  value = azurerm_linux_virtual_machine.console.id
}

output "console_identity_id" {
  value = azurerm_user_assigned_identity.console.id
}

output "workload_identity_id" {
  value = azurerm_user_assigned_identity.workload.id
}

output "workload_identity_client_id" {
  value = azurerm_user_assigned_identity.workload.client_id
}

output "dns_zone_id" {
  value = azurerm_private_dns_zone.this.id
}

output "dns_zone_name" {
  value = azurerm_private_dns_zone.this.name
}

output "data_bucket_id" {
  value = local.data_bucket_id
}

output "data_bucket_endpoint" {
  value = azurerm_storage_account.data.primary_blob_endpoint
}

output "ops_bucket_endpoint" {
  value = azurerm_storage_account.ops.primary_blob_endpoint
}
