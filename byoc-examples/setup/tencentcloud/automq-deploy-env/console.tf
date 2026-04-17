################################################################################
# Console CVM and Dependencies
# All resources in this file are gated by var.enable_console
################################################################################

# ── SSH Key Pair ─────────────────────────────────────────────────────────────

resource "tls_private_key" "console" {
  count     = var.enable_console ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "console_private_key" {
  count           = var.enable_console ? 1 : 0
  content         = tls_private_key.console[0].private_key_pem
  filename        = local.console_private_key_path
  file_permission = "0600"
}

resource "tencentcloud_key_pair" "console" {
  count      = var.enable_console ? 1 : 0
  key_name   = local.console_key_pair_name
  public_key = tls_private_key.console[0].public_key_openssh

  tags = {
    automqVendor        = "automq"
    automqEnvironmentID = var.alias
  }
}

# ── Security Group ───────────────────────────────────────────────────────────

resource "tencentcloud_security_group" "console" {
  count       = var.enable_console ? 1 : 0
  name        = local.console_name
  description = "Security group for AutoMQ BYOC console in environment ${var.alias}"

  tags = {
    automqVendor        = "automq"
    automqEnvironmentID = var.alias
  }
}

resource "tencentcloud_security_group_rule_set" "console" {
  count             = var.enable_console ? 1 : 0
  security_group_id = tencentcloud_security_group.console[0].id

  ingress {
    action     = "ACCEPT"
    protocol   = "TCP"
    cidr_block = "0.0.0.0/0"
    port       = "8080"
  }

  ingress {
    action     = "ACCEPT"
    protocol   = "TCP"
    cidr_block = "0.0.0.0/0"
    port       = "22"
  }

  egress {
    action     = "ACCEPT"
    protocol   = "ALL"
    cidr_block = "0.0.0.0/0"
    port       = "ALL"
  }
}

# ── CAM Role + Policy ────────────────────────────────────────────────────────

resource "tencentcloud_cam_role" "console" {
  count       = var.enable_console ? 1 : 0
  name        = local.console_name
  description = "CAM role for AutoMQ BYOC console CVM"
  document    = <<EOF
{
  "version": "2.0",
  "statement": [
    {
      "action": ["name/sts:AssumeRole"],
      "effect": "allow",
      "principal": { "service": ["cvm.qcloud.com"] }
    }
  ]
}
EOF

  tags = {
    automqVendor        = "automq"
    automqEnvironmentID = var.alias
  }
}

resource "tencentcloud_cam_policy" "console" {
  count       = var.enable_console ? 1 : 0
  name        = local.console_policy_name
  description = "Policy for AutoMQ BYOC console instance"
  document    = <<EOF
{
  "version": "2.0",
  "statement": [
    {
      "effect": "allow",
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
      "resource": [
        "qcs::cos:${var.region}::${local.data_bucket_name}",
        "qcs::cos:${var.region}::${local.data_bucket_name}/*",
        "qcs::cos:${var.region}::${local.ops_bucket_name}",
        "qcs::cos:${var.region}::${local.ops_bucket_name}/*"
      ]
    },
    {
      "effect": "allow",
      "action": [
        "as:DescribeLaunchConfigurations",
        "as:DescribeAutoScalingGroups",
        "as:DescribeAutoScalingInstances",
        "vpc:DescribeVpcEx",
        "vpc:DescribeSubnetEx",
        "tke:DescribeClusterNodePoolDetail",
        "tke:DescribeClusters",
        "tke:DescribeClusterNodePools",
        "privatedns:DescribePrivateZone",
        "privatedns:CreatePrivateZoneRecord",
        "privatedns:DeletePrivateZoneRecord",
        "privatedns:DescribePrivateZoneRecordList"
      ],
      "resource": ["*"]
    }
  ]
}
EOF
}

resource "tencentcloud_cam_role_policy_attachment" "console" {
  count     = var.enable_console ? 1 : 0
  role_id   = tencentcloud_cam_role.console[0].id
  policy_id = tencentcloud_cam_policy.console[0].id
}

# ── Console CVM Instance ─────────────────────────────────────────────────────

data "tencentcloud_images" "console" {
  count            = var.enable_console ? 1 : 0
  image_name_regex = var.console_image_name
}

resource "tencentcloud_eip" "console" {
  count = var.enable_console && var.console_public_access ? 1 : 0
  name  = local.console_name

  tags = {
    automqVendor        = "automq"
    automqEnvironmentID = var.alias
  }
}

resource "tencentcloud_instance" "console" {
  count             = var.enable_console ? 1 : 0
  instance_name     = local.console_instance_name
  instance_type     = var.console_instance_type
  image_id          = data.tencentcloud_images.console[0].images[0].image_id
  availability_zone = data.tencentcloud_vpc_subnets.selected.instance_list[0].availability_zone
  subnet_id         = var.console_subnet_id
  vpc_id            = var.vpc_id

  orderly_security_groups = [tencentcloud_security_group.console[0].id]
  cam_role_name           = tencentcloud_cam_role.console[0].name
  key_ids                 = [tencentcloud_key_pair.console[0].id]

  system_disk_type = "CLOUD_BSSD"
  system_disk_size = 50

  instance_charge_type = "POSTPAID_BY_HOUR"

  user_data = var.console_init ? base64encode(<<-EOT
#cloud-config
runcmd:
  - touch /opt/cmp/config.properties
  - echo "cmp.environmentId=${var.alias}" >> /opt/cmp/config.properties
  - echo "cmp.provider.credential=vm-role://${tencentcloud_cam_role.console[0].name}@tencentcloud" >> /opt/cmp/config.properties
  - echo "cmp.provider.opsBucket=${tencentcloud_cos_bucket.ops_bucket.bucket}" >> /opt/cmp/config.properties
  - echo "cmp.provider.instanceProfile=${tencentcloud_cam_role.console[0].name}" >> /opt/cmp/config.properties
EOT
  ) : null

  tags = {
    automqVendor        = "automq"
    automqEnvironmentID = var.alias
  }

  depends_on = [tencentcloud_cam_role_policy_attachment.console]
}

resource "tencentcloud_eip_association" "console" {
  count       = var.enable_console && var.console_public_access ? 1 : 0
  eip_id      = tencentcloud_eip.console[0].id
  instance_id = tencentcloud_instance.console[0].id
}

# ── Data Volume (CBS disk) ───────────────────────────────────────────────────

resource "tencentcloud_cbs_storage" "console_data" {
  count             = var.enable_console ? 1 : 0
  storage_name      = local.console_data_disk_name
  storage_type      = "CLOUD_BSSD"
  storage_size      = 100
  availability_zone = tencentcloud_instance.console[0].availability_zone
  encrypt           = false

  tags = {
    automqVendor        = "automq"
    automqEnvironmentID = var.alias
  }
}

resource "tencentcloud_cbs_storage_attachment" "console_data" {
  count       = var.enable_console ? 1 : 0
  storage_id  = tencentcloud_cbs_storage.console_data[0].id
  instance_id = tencentcloud_instance.console[0].id
}

# ── Console Outputs ──────────────────────────────────────────────────────────

output "console_endpoint" {
  description = "Console web endpoint URL (public EIP when console_public_access=true, otherwise private IP)"
  value       = var.enable_console ? (
    var.console_public_access
    ? "http://${tencentcloud_eip.console[0].public_ip}:8080"
    : "http://${tencentcloud_instance.console[0].private_ip}:8080"
  ) : ""
}

output "console_initial_username" {
  description = "Console initial admin username"
  value       = var.enable_console ? "admin" : ""
}

output "console_initial_password" {
  description = "Console initial admin password (instance ID)"
  sensitive   = true
  value       = var.enable_console ? tencentcloud_instance.console[0].id : ""
}

output "console_private_key_pem" {
  description = "SSH private key for the console instance"
  sensitive   = true
  value       = var.enable_console ? tls_private_key.console[0].private_key_pem : ""
}

output "console_security_group_id" {
  description = "Console security group ID"
  value       = var.enable_console ? tencentcloud_security_group.console[0].id : ""
}

output "console_cam_role_name" {
  description = "Console CAM role name"
  value       = var.enable_console ? tencentcloud_cam_role.console[0].name : ""
}
