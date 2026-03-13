# TKE Cluster ID
output "tke_cluster_id" {
  description = "The ID of the TKE cluster."
  value       = tencentcloud_kubernetes_cluster.tke.id
}

# CAM Role Name bound to AutoMQ node pool
output "cam_role_name" {
  description = "The CAM role name bound to the AutoMQ node pool."
  value       = tencentcloud_cam_role.automq_node_role.name
}

# Intranet Kubeconfig
output "kube_config_intranet" {
  description = "The intranet kubeconfig for the TKE cluster."
  value       = tencentcloud_kubernetes_cluster.tke.kube_config_intranet
  sensitive   = true
  depends_on  = [tencentcloud_kubernetes_cluster_endpoint.intranet]
}
