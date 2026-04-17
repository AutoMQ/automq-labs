resource "tencentcloud_private_dns_zone" "console" {
  domain = local.console_dns_zone_domain
  remark = "Private DNS zone for AutoMQ BYOC environment"

  vpc_set {
    region      = var.region
    uniq_vpc_id = var.vpc_id
  }
}

output "console_dns_zone_id" {
  value = tencentcloud_private_dns_zone.console.id
}

resource "tencentcloud_cos_bucket" "data_bucket" {
  bucket      = local.data_bucket_name
  acl         = "private"
  force_clean = true

  tags = {
    automqVendor        = "automq"
    automqEnvironmentID = var.alias
  }
}

output "data_bucket_name" {
  value = tencentcloud_cos_bucket.data_bucket.bucket
}


resource "tencentcloud_cam_role" "kafka_role" {
  name        = local.cluster_role_name
  description = "CAM role for AutoMQ TKE node pools in environment ${var.alias}"
  document    = <<EOF
{
  "version": "2.0",
  "statement": [
    {
      "action": [
        "name/sts:AssumeRole"
      ],
      "effect": "allow",
      "principal": {
        "service": [
          "cvm.qcloud.com"
        ]
      }
    }
  ]
}
EOF

  tags = {
    automqVendor        = "automq"
    automqEnvironmentID = var.alias
  }
}

resource "tencentcloud_cam_policy" "custom_policy" {
  name        = local.cluster_policy_name
  description = "Policy for AutoMQ BYOC environment"
  document    = <<EOF
{
  "version": "2.0",
  "statement": [
    {
      "action": [
        "cos:GetBucket",
        "cos:GetBucketACL",
        "cos:GetBucketLifecycle",
        "cos:GetBucketLocation",
        "cos:GetBucketTagging",
        "cos:GetBucketVersionAcl",
        "cos:GetBucketWebsite",
        "cos:HeadBucket",
        "cos:GetObjectACL",
        "cos:GetObjectVersionAcl",
        "cos:GetObjectTagging",
        "cos:AbortMultipartUpload",
        "cos:GetObject",
        "cos:GetService",
        "cos:HeadObject",
        "cos:ListMultipartUploads",
        "cos:ListParts",
        "cos:GetBucketLogging",
        "cos:DeleteBucket",
        "cos:DeleteBucketLifecycle",
        "cos:DeleteBucketPolicy",
        "cos:DeleteBucketTagging",
        "cos:PutBucket",
        "cos:PutBucketACL",
        "cos:PutBucketLifecycle",
        "cos:PutBucketLogging",
        "cos:PutBucketPolicy",
        "cos:PutBucketTagging",
        "cos:PutBucketVersionAcl",
        "cos:PutBucketVersioning",
        "cos:PutBucketWebsite",
        "cos:PutObjectACL",
        "cos:DeleteObjectTagging",
        "cos:PutObjectTagging",
        "cos:CompleteMultipartUpload",
        "cos:DeleteMultipleObjects",
        "cos:DeleteObject",
        "cos:InitiateMultipartUpload",
        "cos:PostObject",
        "cos:PutObject",
        "cos:PutObjectCopy",
        "cos:UploadPart",
        "cos:UploadPartCopy",
        "cos:PutObjectVersionAcl"
      ],
      "effect": "allow",
      "resource": [
        "qcs::cos:${var.region}::${local.ops_bucket_name}",
        "qcs::cos:${var.region}::${local.ops_bucket_name}/*",
        "qcs::cos:${var.region}::${local.data_bucket_name}",
        "qcs::cos:${var.region}::${local.data_bucket_name}/*"
      ]
    },
    {
      "action": [
        "cvm:DescribeUserAvailableZones",
        "cvm:DetachDisks",
        "cvm:DescribeDisks"
      ],
      "effect": "allow",
      "resource": [
        "*"
      ]
    }
  ]
}
EOF
}

output "cam_role_name" {
  value = tencentcloud_cam_role.kafka_role.name
}

resource "tencentcloud_cam_role_policy_attachment" "kafka_role_policy" {
  role_id   = tencentcloud_cam_role.kafka_role.id
  policy_id = tencentcloud_cam_policy.custom_policy.id
}

resource "tencentcloud_kubernetes_node_pool" "automq_node_pool" {
  name       = "automq-node-pool"
  cluster_id = tencentcloud_kubernetes_cluster.main.id

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  min_size         = var.automq_node_pool.min_size
  max_size         = var.automq_node_pool.max_size
  desired_capacity = var.automq_node_pool.desired_capacity

  enable_auto_scale        = true
  multi_zone_subnet_policy = "EQUALITY"
  node_os                  = "tlinux3.1x86_64"
  delete_keep_instance     = false
  retry_policy             = "INCREMENTAL_INTERVALS"

  auto_scaling_config {
    instance_type = var.automq_node_pool.instance_type

    instance_charge_type       = var.automq_node_pool.instance_charge_type
    spot_instance_type         = var.automq_node_pool.instance_charge_type == "SPOTPAID" ? "one-time" : null
    spot_max_price             = var.automq_node_pool.instance_charge_type == "SPOTPAID" ? var.automq_node_pool.spot_max_price : null
    instance_charge_type_prepaid_period       = var.automq_node_pool.instance_charge_type == "PREPAID" ? var.automq_node_pool.prepaid_period : null
    instance_charge_type_prepaid_renew_flag   = var.automq_node_pool.instance_charge_type == "PREPAID" ? var.automq_node_pool.prepaid_renew_flag : null

    system_disk_type   = "CLOUD_BSSD"
    system_disk_size   = 50
    public_ip_assigned = false

    password = random_password.node_password.result

    cam_role_name              = tencentcloud_cam_role.kafka_role.name
    orderly_security_group_ids = [tencentcloud_security_group.cluster_sg.id]

    enhanced_security_service = false
    enhanced_monitor_service  = false
  }

  labels = {
    "automqVendor" = "automq"
  }

  taints {
    key    = "dedicated"
    value  = "automq"
    effect = "NoSchedule"
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
