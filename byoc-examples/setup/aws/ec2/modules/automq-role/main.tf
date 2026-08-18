locals {
  role_name = "automq-data-plane-${var.name_prefix}"
  common_tags = merge(var.tags, {
    ManagedBy    = "terraform"
    automqVendor = "automq"
  })

  base_policy_statements = [
    {
      Sid    = "BucketMetadata"
      Effect = "Allow"
      Action = [
        "s3:GetLifecycleConfiguration",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutLifecycleConfiguration",
      ]
      Resource = [
        "arn:aws:s3:::${var.data_bucket_name}",
        "arn:aws:s3:::${var.ops_bucket_name}",
      ]
    },
    {
      Sid    = "BucketObjects"
      Effect = "Allow"
      Action = [
        "s3:AbortMultipartUpload",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:PutObject",
        "s3:PutObjectTagging",
      ]
      Resource = [
        "arn:aws:s3:::${var.data_bucket_name}/*",
        "arn:aws:s3:::${var.ops_bucket_name}/*",
      ]
    },
    {
      Sid    = "VolumeFailover"
      Effect = "Allow"
      Action = [
        "ec2:AttachVolume",
        "ec2:DetachVolume",
      ]
      Resource = "*"
      Condition = {
        StringEquals = {
          "aws:ResourceTag/automqVendor" = "automq"
        }
      }
    },
    {
      Sid    = "ReadComputeMetadata"
      Effect = "Allow"
      Action = [
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeVolumes",
      ]
      Resource = "*"
    },
    {
      Sid    = "PrivateDns"
      Effect = "Allow"
      Action = [
        "route53:ChangeResourceRecordSets",
        "route53:GetHostedZone",
        "route53:ListResourceRecordSets",
      ]
      Resource = "arn:aws:route53:::hostedzone/${var.hosted_zone_id}"
    },
  ]

  policy_document = {
    Version   = "2012-10-17"
    Statement = local.base_policy_statements
  }
}

resource "aws_iam_role" "this" {
  name = local.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  force_detach_policies = true
  tags                  = local.common_tags
}

resource "aws_iam_policy" "this" {
  name        = "${local.role_name}-policy"
  description = "Permissions for AutoMQ EC2 data-plane nodes"
  policy      = jsonencode(local.policy_document)
  tags        = local.common_tags
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}

resource "aws_iam_instance_profile" "this" {
  name = local.role_name
  role = aws_iam_role.this.name
  tags = local.common_tags
}
