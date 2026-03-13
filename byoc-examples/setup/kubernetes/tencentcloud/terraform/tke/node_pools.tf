# Public Node Pool - 2C4G, 2 nodes, Auto-Scaling enabled
resource "tencentcloud_kubernetes_node_pool" "public" {
  cluster_id           = tencentcloud_kubernetes_cluster.tke.id
  name                 = "public-node-pool"
  node_os              = var.node_os
  max_size             = 10
  min_size             = 2
  desired_capacity     = 2
  enable_auto_scale    = true
  vpc_id               = var.vpc_id
  subnet_ids           = var.subnet_ids
  retry_policy         = "INCREMENTAL_INTERVALS"
  delete_keep_instance = false

  auto_scaling_config {
    instance_type              = var.public_instance_type
    instance_charge_type       = var.instance_charge_type
    spot_instance_type         = var.instance_charge_type == "SPOTPAID" ? "one-time" : null
    spot_max_price             = var.instance_charge_type == "SPOTPAID" ? var.spot_max_price : null
    system_disk_type           = "CLOUD_PREMIUM"
    system_disk_size           = 50
    key_ids                    = var.key_ids
    orderly_security_group_ids = var.security_group_ids
  }
}

# AutoMQ Dedicated Node Pool - user instance type, 3 nodes, CAM role, taint
resource "tencentcloud_kubernetes_node_pool" "automq" {
  cluster_id           = tencentcloud_kubernetes_cluster.tke.id
  name                 = local.automq_node_pool_name
  node_os              = var.node_os
  max_size             = 10
  min_size             = 3
  desired_capacity     = 3
  enable_auto_scale    = false
  vpc_id               = var.vpc_id
  subnet_ids           = var.subnet_ids
  retry_policy         = "INCREMENTAL_INTERVALS"
  delete_keep_instance = false

  auto_scaling_config {
    instance_type              = var.instance_type
    instance_charge_type       = var.instance_charge_type
    spot_instance_type         = var.instance_charge_type == "SPOTPAID" ? "one-time" : null
    spot_max_price             = var.instance_charge_type == "SPOTPAID" ? var.spot_max_price : null
    system_disk_type           = "CLOUD_HSSD"
    system_disk_size           = 50
    cam_role_name              = tencentcloud_cam_role.automq_node_role.name
    key_ids                    = var.key_ids
    orderly_security_group_ids = var.security_group_ids
  }

  taints {
    key    = "dedicated"
    value  = "automq"
    effect = "NoSchedule"
  }
}
