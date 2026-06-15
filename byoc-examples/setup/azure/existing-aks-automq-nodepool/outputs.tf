output "aks_id" {
  description = "Existing AKS cluster resource ID."
  value       = data.azurerm_kubernetes_cluster.aks.id
}

output "aks_node_resource_group" {
  description = "Node resource group of the existing AKS cluster."
  value       = data.azurerm_kubernetes_cluster.aks.node_resource_group
}

output "automq_nodepool_id" {
  description = "AutoMQ node pool resource ID."
  value       = azurerm_kubernetes_cluster_node_pool.automq.id
}

output "automq_nodepool_name" {
  description = "AutoMQ node pool name."
  value       = azurerm_kubernetes_cluster_node_pool.automq.name
}

output "automq_nodepool_vmss_id" {
  description = "VMSS resource ID backing the AutoMQ node pool."
  value       = local.vmss_id
}
