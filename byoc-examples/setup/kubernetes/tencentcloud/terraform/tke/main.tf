# TKE Cluster
resource "tencentcloud_kubernetes_cluster" "tke" {
  cluster_name               = local.cluster_name
  cluster_version            = var.tke_cluster_version
  cluster_deploy_type        = "MANAGED_CLUSTER"
  cluster_level              = "L20"
  auto_upgrade_cluster_level = true
  vpc_id                     = var.vpc_id
  network_type               = "VPC-CNI"
  eni_subnet_ids             = var.subnet_ids
  service_cidr               = var.service_cidr
  cluster_max_service_num    = 4096
  cluster_os                 = "tlinux2.2(tkernel3)x86_64"
  container_runtime          = "containerd"

  # Prometheus plugin
  extension_addon {
    name  = "tke-prometheus"
    param = jsonencode({})
  }

  lifecycle {
    precondition {
      condition     = length(var.availability_zones) == length(var.subnet_ids)
      error_message = "availability_zones and subnet_ids must have the same length."
    }
  }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Enable intranet API Server endpoint
resource "tencentcloud_kubernetes_cluster_endpoint" "intranet" {
  cluster_id                 = tencentcloud_kubernetes_cluster.tke.id
  cluster_intranet           = true
  cluster_intranet_subnet_id = var.subnet_ids[0]

  depends_on = [
    tencentcloud_kubernetes_node_pool.public,
    tencentcloud_kubernetes_node_pool.automq,
  ]
}
