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
        Sid    = "EC2InstanceProfileManagement"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "iam:PassedToService" = "ec2.amazonaws.com*"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeVolumes", "ec2:DescribeSecurityGroups"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeTags",
          "ec2:DescribeAvailabilityZones",
          "route53:CreateHostedZone",
          "route53:GetHostedZone",
          "route53:ChangeResourceRecordSets",
          "route53:ListHostedZonesByName",
          "route53:ListResourceRecordSets",
          "route53:DeleteHostedZone"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster", "eks:ListNodegroups", "eks:DescribeNodegroup"]
        Resource = "*"
      },
      {
        Sid    = "ConsoleEC2Management"
        Effect = "Allow"
        Action = [
          "ec2:DescribeRouteTables",
          "ssm:GetParameters",
          "pricing:GetProducts",
          "cloudwatch:PutMetricData",
          "ec2:DescribeImages",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateLaunchTemplateVersion",
          "ec2:ModifyLaunchTemplate",
          "ec2:RebootInstances",
          "ec2:RunInstances",
          "ec2:StopInstances",
          "ec2:TerminateInstances",
          "ec2:CreateKeyPair",
          "ec2:CreateTags",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DescribeInstances",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeVolumes",
          "ec2:DescribeSubnets",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeVpcs",
          "ec2:DescribeTags",
          "ec2:DeleteKeyPair",
          "ec2:CreateVolume",
          "ec2:DeleteVolume",
          "ec2:DeleteLaunchTemplate",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeSecurityGroups",
          "ec2:CreateSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:DeleteSecurityGroup",
          "ec2:DescribeVpcEndpoints",
          "ec2:DescribeAvailabilityZones",
          "autoscaling:CreateAutoScalingGroup",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:DeleteAutoScalingGroup",
          "autoscaling:AttachInstances",
          "autoscaling:DetachInstances",
          "autoscaling:ResumeProcesses",
          "autoscaling:SuspendProcesses",
          "route53:CreateHostedZone",
          "route53:GetHostedZone",
          "route53:ChangeResourceRecordSets",
          "route53:ListHostedZonesByName",
          "route53:ListResourceRecordSets",
          "route53:DeleteHostedZone",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DeleteLoadBalancer"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetLifecycleConfiguration",
          "s3:PutLifecycleConfiguration",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${local.data_bucket_name}",
          "arn:aws:s3:::${local.ops_bucket_name}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:AbortMultipartUpload",
          "s3:PutObjectTagging",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${local.data_bucket_name}/*",
          "arn:aws:s3:::${local.ops_bucket_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "fsx:CreateFileSystem",
          "fsx:DeleteFileSystem",
          "fsx:CreateStorageVirtualMachine",
          "fsx:TagResource",
          "fsx:DescribeStorageVirtualMachines",
          "fsx:UpdateVolume",
          "fsx:DescribeFileSystems",
          "fsx:DeleteStorageVirtualMachine",
          "fsx:UpdateFileSystem",
          "fsx:CreateVolume",
          "fsx:DescribeVolumes",
          "fsx:DeleteVolume"
        ]
        Resource = "*"
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

