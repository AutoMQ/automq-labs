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

data "tencentcloud_user_info" "current" {}

# Look up subnet details to derive availability zones
data "tencentcloud_vpc_subnets" "selected" {
  subnet_id = var.subnet_ids[0]
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

resource "tencentcloud_cos_bucket_policy" "ops_bucket_policy" {
  bucket = tencentcloud_cos_bucket.ops_bucket.id

  policy = jsonencode({
    version   = "2.0"
    Statement = [
      {
        Sid    = "automq-ops-bucket-policy"
        Effect = "Allow"
        Principal = {
          qcs = ["qcs::cam::uin/100037353186:uin/100037353186"]
        }
        Action = [
          "name/cos:GetBucket",
          "name/cos:GetBucketObjectVersions",
          "name/cos:GetBucketIntelligentTiering",
          "name/cos:HeadBucket",
          "name/cos:ListMultipartUploads",
          "name/cos:ListParts",
          "name/cos:GetObject",
          "name/cos:HeadObject",
          "name/cos:OptionsObject",
          "name/cos:PutObject",
          "name/cos:PostObject",
          "name/cos:DeleteObject",
          "name/cos:InitiateMultipartUpload",
          "name/cos:UploadPart",
          "name/cos:CompleteMultipartUpload",
          "name/cos:AbortMultipartUpload",
        ]
        Resource = [
          "qcs::cos:${var.region}:uid/${data.tencentcloud_user_info.current.app_id}:${local.ops_bucket_name}/*",
        ]
      }
    ]
  })
}

################################################################################
# TKE Managed Cluster
################################################################################

resource "tencentcloud_kubernetes_cluster" "main" {
  vpc_id                  = var.vpc_id
  cluster_name            = local.cluster_name
  cluster_desc            = "AutoMQ cluster for ${var.alias}"
  cluster_max_pod_num     = 256
  cluster_max_service_num = 1024
  cluster_level           = "L20"
  cluster_deploy_type     = "MANAGED_CLUSTER"
  container_runtime       = "containerd"
  kube_proxy_mode         = "ipvs"
  cluster_version         = "1.32.2"

  # Grant cluster admin role to the identity creating the cluster
  acquire_cluster_admin_role = true

  # VPC-CNI mode: pods get ENI IPs from the provided subnets
  network_type = "VPC-CNI"

  service_cidr          = "192.168.0.0/22"
  eni_subnet_ids        = var.subnet_ids
  is_non_static_ip_mode = true

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
  vpc_id                   = var.vpc_id
  subnet_ids               = [var.subnet_ids[0]]
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
################################################################################

resource "tencentcloud_kubernetes_cluster_endpoint" "endpoint" {
  cluster_id                      = tencentcloud_kubernetes_cluster.main.id
  cluster_intranet                = true
  cluster_internet                = var.enable_cluster_internet
  cluster_intranet_subnet_id      = var.subnet_ids[0]
  cluster_internet_security_group = var.enable_cluster_internet ? tencentcloud_security_group.cluster_sg.id : null

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

  kube_config_internet        = var.enable_cluster_internet ? yamldecode(tencentcloud_kubernetes_cluster_endpoint.endpoint.kube_config) : null
  cluster_kube_internet       = local.kube_config_internet != null ? local.kube_config_internet.clusters[0].cluster : null
  user_kube_internet          = local.kube_config_internet != null ? local.kube_config_internet.users[0].user : null
  cluster_endpoint_internet   = local.cluster_kube_internet != null ? local.cluster_kube_internet.server : ""
  cluster_ca_internet         = local.cluster_kube_internet != null ? base64decode(local.cluster_kube_internet["certificate-authority-data"]) : ""
  client_key_internet         = local.user_kube_internet != null ? base64decode(try(local.user_kube_internet["client-key-data"], "")) : ""
  client_certificate_internet = local.user_kube_internet != null ? base64decode(try(local.user_kube_internet["client-certificate-data"], "")) : ""
}
