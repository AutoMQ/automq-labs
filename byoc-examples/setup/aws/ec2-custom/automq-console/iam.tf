resource "aws_iam_role" "console" {
  name = "automq-console-${local.name_suffix}"

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

locals {
  console_policy_statements = [
    {
      Sid      = "PassAutoMQDataPlaneRole"
      Effect   = "Allow"
      Action   = "iam:PassRole"
      Resource = module.automq_role.role_arn
      Condition = {
        StringLike = {
          "iam:PassedToService" = "ec2.amazonaws.com*"
        }
      }
    },
    {
      Sid    = "OpsBucketMetadata"
      Effect = "Allow"
      Action = [
        "s3:GetBucketPolicy",
        "s3:GetLifecycleConfiguration",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutBucketPolicy",
        "s3:PutBucketTagging",
        "s3:PutLifecycleConfiguration",
      ]
      Resource = "arn:aws:s3:::${local.ops_bucket_name}"
    },
    {
      Sid    = "OpsBucketObjects"
      Effect = "Allow"
      Action = [
        "s3:AbortMultipartUpload",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:PutObject",
        "s3:PutObjectTagging",
      ]
      Resource = "arn:aws:s3:::${local.ops_bucket_name}/*"
    },
    {
      Sid    = "ManageTaggedCompute"
      Effect = "Allow"
      Action = [
        "autoscaling:AttachInstances",
        "autoscaling:DeleteAutoScalingGroup",
        "autoscaling:DetachInstances",
        "autoscaling:ResumeProcesses",
        "autoscaling:SuspendProcesses",
        "autoscaling:UpdateAutoScalingGroup",
        "ec2:AttachVolume",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:DeleteKeyPair",
        "ec2:DeleteNetworkInterface",
        "ec2:DeleteSecurityGroup",
        "ec2:DeleteVolume",
        "ec2:DetachVolume",
        "ec2:RebootInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances",
      ]
      Resource = "*"
      Condition = {
        StringEquals = {
          "aws:ResourceTag/automqVendor" = "automq"
        }
      }
    },
    {
      Sid    = "ProvisionCompute"
      Effect = "Allow"
      Action = [
        "autoscaling:CreateAutoScalingGroup",
        "autoscaling:DescribeAutoScalingGroups",
        "ec2:CreateKeyPair",
        "ec2:CreateLaunchTemplate",
        "ec2:CreateLaunchTemplateVersion",
        "ec2:CreateNetworkInterface",
        "ec2:CreateSecurityGroup",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:DeleteLaunchTemplate",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceAttribute",
        "ec2:DescribeInstanceTypeOfferings",
        "ec2:DescribeInstances",
        "ec2:DescribeKeyPairs",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeNetworkInterfaceAttribute",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroupRules",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DescribeVpcEndpoints",
        "ec2:DescribeVpcs",
        "ec2:ModifyLaunchTemplate",
        "ec2:RunInstances",
        "elasticloadbalancing:DescribeTargetGroups",
        "pricing:DescribeServices",
        "pricing:GetAttributeValues",
        "pricing:GetProducts",
        "ssm:GetParameters",
      ]
      Resource = "*"
    },
    {
      Sid      = "CreateAutoScalingServiceRole"
      Effect   = "Allow"
      Action   = "iam:CreateServiceLinkedRole"
      Resource = "*"
      Condition = {
        StringEquals = {
          "iam:AWSServiceName" = "autoscaling.amazonaws.com"
        }
      }
    },
    {
      Sid    = "PrivateDns"
      Effect = "Allow"
      Action = [
        "route53:ChangeResourceRecordSets",
        "route53:GetHostedZone",
        "route53:ListResourceRecordSets",
      ]
      Resource = aws_route53_zone.private.arn
    }
  ]

  console_policy_document = {
    Version   = "2012-10-17"
    Statement = local.console_policy_statements
  }
}

resource "aws_iam_policy" "console" {
  name        = "automq-console-${local.name_suffix}"
  description = "Permissions for the AutoMQ BYOC Console"
  policy      = jsonencode(local.console_policy_document)
  tags        = local.common_tags
}

resource "aws_iam_role_policy_attachment" "console" {
  role       = aws_iam_role.console.name
  policy_arn = aws_iam_policy.console.arn
}

resource "aws_iam_role_policy_attachment" "console_ssm" {
  role       = aws_iam_role.console.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "console" {
  name = "automq-console-${local.name_suffix}"
  role = aws_iam_role.console.name
  tags = local.common_tags
}
