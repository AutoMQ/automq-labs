terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = "~> 1.3"
}

provider "aws" {
  region = var.region
}

resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

locals {
  automq_byoc_eks_node_role_arn = aws_iam_role.node_group_role.arn
  resource_suffix = "${random_string.suffix.result}-${var.resource_suffix}"
  policy_name = "policy-${local.resource_suffix}"
  node_group_role_name = "node-group-role-${local.resource_suffix}"
}

resource "aws_iam_role" "node_group_role" {
  name = local.node_group_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  force_detach_policies = true
}

resource "aws_iam_instance_profile" "node_group_instance_profile" {
  name = local.node_group_role_name
  role = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "nodes-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "nodes-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "nodes-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group_role.name
}

# Create IAM policy
resource "aws_iam_policy" "custom_policy" {
  name = local.policy_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetLifecycleConfiguration",
          "s3:PutLifecycleConfiguration",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::${var.data_bucket_name}",
          "arn:aws:s3:::${var.ops_bucket_name}"
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
          "arn:aws:s3:::${var.data_bucket_name}/*",
          "arn:aws:s3:::${var.ops_bucket_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AttachVolume",
          "ec2:DetachVolume",
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "policy_attachment" {
  role       = aws_iam_role.node_group_role.name
  policy_arn = aws_iam_policy.custom_policy.arn
}

resource "aws_iam_role_policy_attachment" "automq-policy" {
  policy_arn = aws_iam_policy.custom_policy.arn
  role       = aws_iam_role.node_group_role.name
}
