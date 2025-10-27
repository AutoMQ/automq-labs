resource "aws_iam_role" "automq_byoc_role" {
  name = "automq-byoc-role-${local.name_suffix}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "automq_console_policy" {
  name = "automq-console-policy-${local.name_suffix}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "*"
        Condition = {
          StringLike = {
            "iam:PassedToService" = "ec2.amazonaws.com*"
          }
        }
      },
      {
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
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteVolume",
          "ec2:DetachVolume",
          "ec2:RebootInstances",
          "ec2:StopInstances",
          "ec2:TerminateInstances",
          "fsx:DeleteFileSystem",
          "fsx:DeleteStorageVirtualMachine",
          "fsx:DeleteVolume",
          "fsx:UpdateFileSystem",
          "fsx:UpdateVolume"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/automqVendor" = "automq"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:PutObject",
          "s3:PutObjectTagging"
        ]
        Resource = [
          "arn:aws:s3:::${local.data_bucket_name}/*",
          "arn:aws:s3:::${local.ops_bucket_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "CreateServiceLinkedRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "autoscaling.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:CreateAutoScalingGroup",
          "autoscaling:DescribeAutoScalingGroups",
          "ec2:CreateKeyPair",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateLaunchTemplateVersion",
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
          "eks:DescribeCluster",
          "eks:DescribeNodegroup",
          "eks:ListClusters",
          "eks:ListNodegroups",
          "elasticloadbalancing:DescribeTargetGroups",
          "fsx:CreateFileSystem",
          "fsx:CreateStorageVirtualMachine",
          "fsx:CreateVolume",
          "fsx:DescribeFileSystems",
          "fsx:DescribeStorageVirtualMachines",
          "fsx:DescribeVolumes",
          "fsx:TagResource",
          "pricing:DescribeServices",
          "pricing:GetAttributeValues",
          "pricing:GetProducts",
          "route53:ChangeResourceRecordSets",
          "route53:GetHostedZone",
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName",
          "route53:ListHostedZonesByVpc",
          "route53:ListResourceRecordSets",
          "s3:AbortMultipartUpload",
          "s3:CreateBucket",
          "s3:DeleteObject",
          "s3:ListAllMyBuckets",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "ssm:GetParameters"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetLifecycleConfiguration",
          "s3:ListBucket",
          "s3:PutLifecycleConfiguration"
        ]
        Resource = [
          "arn:aws:s3:::${local.ops_bucket_name}"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "automq_console_attach" {
  role       = aws_iam_role.automq_byoc_role.name
  policy_arn = aws_iam_policy.automq_console_policy.arn
}

resource "aws_iam_instance_profile" "automq_byoc_instance_profile" {
  name = "automq-byoc-instance-profile-${local.name_suffix}"
  role = aws_iam_role.automq_byoc_role.name
}
