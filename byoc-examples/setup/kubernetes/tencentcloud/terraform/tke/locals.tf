# Centralized management of local variables
locals {
  # Random suffix for unique naming
  suffix = random_string.suffix.result

  # Cluster Name
  cluster_name = var.tke_cluster_name

  # CAM Role Name
  cam_role_name = "automq-node-role-${local.suffix}"

  # AutoMQ Node Pool Name
  automq_node_pool_name = "automq-${local.suffix}"

  # Common Tags
  common_tags = merge(
    {
      Project     = var.tke_cluster_name
      ManagedBy   = "terraform"
      provisioner = "automq"
    },
    var.common_tags
  )
}
