# Azure Red Hat OpenShift Cluster
resource "azurerm_redhat_openshift_cluster" "aro" {
  count               = var.create_openshift_cluster ? 1 : 0
  name                = var.openshift_cluster_name != null ? var.openshift_cluster_name : "aro-${local.name_suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  cluster_profile {
    domain       = "${var.openshift_cluster_name != null ? var.openshift_cluster_name : local.name_suffix}.${var.location}.aroapp.io"
    fips_enabled = false
    pull_secret  = null # Optional: provide pull secret if needed
    # resource_group_id is automatically computed by Azure, cannot be set manually
    version = var.openshift_version != null ? var.openshift_version : "4.18.26" # Default to a recent stable version
  }

  network_profile {
    pod_cidr     = "10.128.0.0/14"
    service_cidr = "172.30.0.0/16"
  }

  # Main profile (control plane)
  main_profile {
    subnet_id = module.network.master_subnet_id
    vm_size   = var.master_vm_size
  }

  # API server profile (required)
  api_server_profile {
    visibility = "Public"
  }

  # Ingress profile (required)
  ingress_profile {
    visibility = "Public"
  }

  # Default worker profile
  worker_profile {
    vm_size      = var.worker_vm_size
    disk_size_gb = 128
    subnet_id    = module.network.worker_subnet_id
    node_count   = var.worker_node_count
  }

  service_principal {
    client_id     = local.service_principal_client_id
    client_secret = local.service_principal_client_secret
  }

  tags = {
    purpose    = "AutoMQ Enterprise"
    managed_by = "terraform"
  }
}

# Outputs for OpenShift cluster
output "openshift_cluster_id" {
  description = "OpenShift cluster resource ID"
  value       = var.create_openshift_cluster ? azurerm_redhat_openshift_cluster.aro[0].id : null
}

output "openshift_cluster_name" {
  description = "OpenShift cluster name"
  value       = var.create_openshift_cluster ? azurerm_redhat_openshift_cluster.aro[0].name : null
}

output "openshift_console_url" {
  description = "OpenShift console URL"
  value       = var.create_openshift_cluster ? azurerm_redhat_openshift_cluster.aro[0].console_url : null
}

# Note: API server URL and kubeadmin credentials are not available as Terraform outputs.
# To get these values, use Azure CLI:
#   az aro show --resource-group <rg> --name <cluster-name> --query "apiserverProfile.url" -o tsv
#   az aro list-credentials --resource-group <rg> --name <cluster-name>
output "openshift_api_server_url_note" {
  description = "Note: Use 'az aro show' to get API server URL"
  value       = var.create_openshift_cluster ? "Run: az aro show --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_redhat_openshift_cluster.aro[0].name} --query 'apiserverProfile.url' -o tsv" : null
}

output "openshift_kubeadmin_credentials_note" {
  description = "Note: Use 'az aro list-credentials' to get kubeadmin username and password"
  value       = var.create_openshift_cluster ? "Run: az aro list-credentials --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_redhat_openshift_cluster.aro[0].name}" : null
}


