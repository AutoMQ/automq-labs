# Centralized management of local variables
# 
# This file contains all static local variables
locals {
  # Cluster Name
  cluster_name = var.oke_cluster_name
  cluster_id   = data.oci_containerengine_clusters.cluster.clusters[0].id
  # Common Tags
  common_tags = merge(
    {
      Project     = var.oke_cluster_name
      ManagedBy   = "terraform"
      provisioner = "automq"
    },
    var.common_tags
  )
}