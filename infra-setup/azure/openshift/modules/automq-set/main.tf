variable "cluster_name" {
  type        = string
  description = "Name of the Azure Red Hat OpenShift cluster"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name where the cluster is located"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the AutoMQ node pool"
}

variable "vnet_name" {
  type        = string
  description = "Virtual Network name for the AutoMQ node pool"
}

variable "subnet_name" {
  type        = string
  description = "Subnet name for the AutoMQ node pool"
}

variable "network_resource_group" {
  type        = string
  description = "Resource group name where the network resources are located"
}

variable "vm_size" {
  type        = string
  description = "VM size for AutoMQ nodes (e.g., Standard_D4s_v3)"
  default     = "Standard_D4s_v3"
}

variable "node_count" {
  type        = number
  description = "Number of nodes in the AutoMQ node pool"
  default     = 3
}

variable "disk_size_gb" {
  type        = number
  description = "Disk size in GB for each node"
  default     = 128
}

variable "location" {
  type        = string
  description = "Azure region where the cluster is located"
}

# Note: Azure Red Hat OpenShift doesn't support adding multiple worker profiles via Terraform.
# We need to use OpenShift Machine Sets to add additional worker nodes.
# This resource will execute a script to create Machine Sets after cluster creation.
resource "null_resource" "automq_nodepool" {
  triggers = {
    cluster_name         = var.cluster_name
    resource_group       = var.resource_group_name
    subnet_id            = var.subnet_id
    vnet_name            = var.vnet_name
    subnet_name          = var.subnet_name
    network_resource_group = var.network_resource_group
    vm_size              = var.vm_size
    node_count           = var.node_count
    disk_size_gb         = var.disk_size_gb
    location             = var.location
  }

  # Ensure this runs after cluster is fully provisioned and accessible
  depends_on = []

  provisioner "local-exec" {
    command     = "${path.module}/create-machineset.sh ${var.cluster_name} ${var.resource_group_name} '${var.subnet_id}' '${var.vnet_name}' '${var.subnet_name}' '${var.network_resource_group}' ${var.vm_size} ${var.node_count} ${var.disk_size_gb} ${var.location}"
    interpreter = ["bash", "-c"]
    on_failure  = continue
  }

  # Destroy provisioner to remove the Machine Sets
  provisioner "local-exec" {
    when        = destroy
    command     = <<-EOT
      echo "To remove AutoMQ nodes, delete the Machine Sets from OpenShift cluster:"
      echo "oc delete machineset -l machine.openshift.io/cluster-api-machineset -n openshift-machine-api --selector=machine.openshift.io/cluster-api-machineset | grep automq"
      echo "Or manually: oc delete machineset <cluster-id>-automq-<zone> -n openshift-machine-api"
    EOT
    interpreter = ["bash", "-c"]
    on_failure  = continue
  }
}

output "nodepool_name" {
  description = "Name prefix for AutoMQ Machine Sets"
  value       = "automq"
}

output "instructions" {
  description = "Instructions for verifying the AutoMQ node pool"
  value       = "After applying, check nodes with: oc get nodes -l node-role.kubernetes.io/automq"
}

