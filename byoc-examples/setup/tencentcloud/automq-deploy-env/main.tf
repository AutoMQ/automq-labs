terraform {
  required_providers {
    tencentcloud = {
      source = "tencentcloudstack/tencentcloud"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

provider "tencentcloud" {
  region = var.region
}

resource "random_password" "node_password" {
  length  = 16
  special = true
}

################################################################################
# Data Sources
################################################################################

data "tencentcloud_availability_zones_by_product" "available_azs" {
  product = "cvm"
}

data "tencentcloud_user_info" "current" {}


locals {
  # Use explicit AZs when provided; otherwise discover up to 3 zones in the region.
  discovered_availability_zones = data.tencentcloud_availability_zones_by_product.available_azs.zones[*].name
  final_availability_zones      = length(var.availability_zones) > 0 ? slice(var.availability_zones, 0, min(length(var.availability_zones), 3)) : slice(local.discovered_availability_zones, 0, min(length(local.discovered_availability_zones), 3))
  az_count                      = length(local.final_availability_zones)
  azs                           = local.final_availability_zones
}

################################################################################
# VPC & Networking
################################################################################

resource "tencentcloud_vpc" "main" {
  name       = local.vpc_name
  cidr_block = "10.0.0.0/16"

  tags = {
    automqVendor        = "automq"
    automqEnvironmentID = var.alias
  }
}

# Public subnet for Console instance placement
resource "tencentcloud_subnet" "public" {
  vpc_id            = tencentcloud_vpc.main.id
  name              = local.public_subnet_name
  cidr_block        = "10.0.0.0/20"
  availability_zone = local.azs[0]
  route_table_id    = tencentcloud_route_table.public.id

  tags = {
    automqVendor        = "automq"
    automqEnvironmentID = var.alias
  }
}

# Private subnets for TKE ENI (VPC-CNI mode), one per AZ
resource "tencentcloud_subnet" "private" {
  count             = local.az_count
  vpc_id            = tencentcloud_vpc.main.id
  name              = "${local.private_subnet_name_prefix}-${count.index}"
  cidr_block        = "10.0.${16 + count.index * 16}.0/20"
  availability_zone = local.azs[count.index]
  route_table_id    = tencentcloud_route_table.private.id
  is_multicast      = false

  tags = {
    automqVendor        = "automq"
    automqEnvironmentID = var.alias
  }
}

# Route tables
resource "tencentcloud_route_table" "public" {
  vpc_id = tencentcloud_vpc.main.id
  name   = local.public_route_table_name
}

resource "tencentcloud_route_table" "private" {
  vpc_id = tencentcloud_vpc.main.id
  name   = local.private_route_table_name
}

# EIP + NAT Gateway for private subnet outbound traffic
resource "tencentcloud_eip" "nat" {
  name = local.nat_eip_name
  tags = {
    automqVendor = "automq"
  }
}

resource "tencentcloud_nat_gateway" "main" {
  name                = local.nat_gateway_name
  vpc_id              = tencentcloud_vpc.main.id
  nat_product_version = 2
  # If `nat_product_version` is 2, `max_concurrent` can only be set to `2000000` or not set at all.
  assigned_eip_set = [tencentcloud_eip.nat.public_ip]

  tags = {
    automqVendor = "automq"
  }
}

resource "tencentcloud_route_table_entry" "private_to_nat" {
  route_table_id         = tencentcloud_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  next_type              = "NAT"
  next_hub               = tencentcloud_nat_gateway.main.id
}

################################################################################
# Security Group for TKE Cluster
################################################################################

resource "tencentcloud_security_group" "cluster_sg" {
  name        = local.cluster_security_group_name
  description = local.cluster_security_group_desc

  tags = {
    automqVendor        = "automq"
    automqEnvironmentID = var.alias
  }
}

resource "tencentcloud_security_group_rule_set" "cluster_sg_rules" {
  security_group_id = tencentcloud_security_group.cluster_sg.id

  ingress {
    action     = "ACCEPT"
    protocol   = "ALL"
    cidr_block = "0.0.0.0/0"
    port       = "ALL"
  }
  egress {
    action     = "ACCEPT"
    protocol   = "ALL"
    cidr_block = "0.0.0.0/0"
    port       = "ALL"
  }
}

################################################################################
# COS Ops Bucket
################################################################################

resource "tencentcloud_cos_bucket" "ops_bucket" {
  bucket      = local.ops_bucket_name
  acl         = "private"
  force_clean = true

  tags = {
    automqVendor        = "automq"
    automqEnvironmentID = var.alias
  }
}

################################################################################
# TKE Managed Cluster
################################################################################

resource "tencentcloud_kubernetes_cluster" "main" {
  vpc_id                  = tencentcloud_vpc.main.id
  cluster_name            = local.cluster_name
  cluster_desc            = "AutoMQ cluster for ${var.alias}"
  cluster_max_pod_num     = 256
  cluster_max_service_num = 1024
  cluster_level           = "L20"
  cluster_deploy_type     = "MANAGED_CLUSTER"
  container_runtime       = "containerd"
  kube_proxy_mode         = "ipvs"
  cluster_version         = "1.32.2"

  # Grant cluster admin role to the identity creating the cluster (e.g., lark-saml)
  acquire_cluster_admin_role = true

  # VPC-CNI mode: pods get ENI IPs from private subnets
  network_type = "VPC-CNI"

  service_cidr          = "192.168.0.0/22"
  eni_subnet_ids        = tencentcloud_subnet.private[*].id
  is_non_static_ip_mode = true # 非固定 IP 模式，解决 CannotPatchENIIP 问题

  # Note: Do not set cluster_internet/cluster_intranet here
  # Use tencentcloud_kubernetes_cluster_endpoint resources instead

  tags = {
    automqVendor        = "automq"
    automqEnvironmentID = var.alias
  }
}

################################################################################
# Node Pools
################################################################################

# System node pool — Spot, for system components
resource "tencentcloud_kubernetes_node_pool" "system" {
  name                     = local.system_node_pool_name
  cluster_id               = tencentcloud_kubernetes_cluster.main.id
  max_size                 = 3
  min_size                 = 1
  vpc_id                   = tencentcloud_vpc.main.id
  subnet_ids               = [tencentcloud_subnet.private[0].id]
  retry_policy             = "INCREMENTAL_INTERVALS"
  desired_capacity         = 3
  enable_auto_scale        = true
  multi_zone_subnet_policy = "EQUALITY"
  node_os                  = "tlinux3.1x86_64"
  delete_keep_instance     = false

  auto_scaling_config {
    instance_type    = "SA9.MEDIUM4"
    system_disk_type = "CLOUD_BSSD"
    system_disk_size = 50


    instance_charge_type = "SPOTPAID"
    spot_instance_type   = "one-time"
    spot_max_price       = "1000"
    public_ip_assigned   = false

    password = random_password.node_password.result

    enhanced_security_service  = false
    enhanced_monitor_service   = false
    orderly_security_group_ids = [tencentcloud_security_group.cluster_sg.id]
  }

  tags = {
    automqVendor        = "automq"
    automqEnvironmentID = var.alias
  }

  depends_on = [tencentcloud_kubernetes_cluster.main]
}

################################################################################
# TKE Cluster Endpoint
# Use intranet endpoint for cluster access from within VPC
################################################################################

resource "tencentcloud_kubernetes_cluster_endpoint" "endpoint" {
  cluster_id                      = tencentcloud_kubernetes_cluster.main.id
  cluster_intranet                = true
  cluster_internet                = true
  cluster_intranet_subnet_id      = tencentcloud_subnet.private[0].id
  cluster_internet_security_group = tencentcloud_security_group.cluster_sg.id

  depends_on = [tencentcloud_kubernetes_node_pool.system]
}

locals {
  kube_config_intranet        = yamldecode(tencentcloud_kubernetes_cluster_endpoint.endpoint.kube_config_intranet)
  cluster_kube_intranet       = local.kube_config_intranet.clusters[0].cluster
  user_kube_intranet          = local.kube_config_intranet.users[0].user
  cluster_endpoint_intranet   = local.cluster_kube_intranet.server
  cluster_ca_intranet         = base64decode(local.cluster_kube_intranet["certificate-authority-data"])
  client_key_intranet         = base64decode(try(local.user_kube_intranet["client-key-data"], ""))
  client_certificate_intranet = base64decode(try(local.user_kube_intranet["client-certificate-data"], ""))

  kube_config_internet        = yamldecode(tencentcloud_kubernetes_cluster_endpoint.endpoint.kube_config)
  cluster_kube_internet       = local.kube_config_internet.clusters[0].cluster
  user_kube_internet          = local.kube_config_internet.users[0].user
  cluster_endpoint_internet   = local.cluster_kube_internet.server
  cluster_ca_internet         = base64decode(local.cluster_kube_internet["certificate-authority-data"])
  client_key_internet         = base64decode(try(local.user_kube_internet["client-key-data"], ""))
  client_certificate_internet = base64decode(try(local.user_kube_internet["client-certificate-data"], ""))
}
