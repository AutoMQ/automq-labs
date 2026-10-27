terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "region" {
  description = "AWS Region of the BYOC EC2 instances"
  type        = string
}

variable "automq_role_arn" {
  description = "AutoMQ IAM Role allowed to assume the customer SSM operator Role"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+", var.automq_role_arn))
    error_message = "automq_role_arn must be an IAM Role ARN."
  }
}

variable "external_id" {
  description = "External ID agreed with AutoMQ"
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.external_id)) > 0
    error_message = "external_id must not be empty."
  }
}

variable "role_name" {
  description = "Name of the customer SSM operator Role"
  type        = string
  default     = "automq-ssm-operator"
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "ssm_operator" {
  name = var.role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = var.automq_role_arn }
      Condition = { StringEquals = { "sts:ExternalId" = var.external_id } }
    }]
  })
}

resource "aws_iam_role_policy" "ssm_operator" {
  name = "ssm-operator"
  role = aws_iam_role.ssm_operator.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StartSessionOnTaggedInstances"
        Effect   = "Allow"
        Action   = "ssm:StartSession"
        Resource = "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          StringEquals = { "ssm:resourceTag/automqVendor" = "automq" }
        }
      },
      {
        Sid      = "UseShellDocument"
        Effect   = "Allow"
        Action   = "ssm:StartSession"
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:document/SSM-SessionManagerRunShell"
      },
      {
        Sid      = "ManageOwnSessions"
        Effect   = "Allow"
        Action   = ["ssm:ResumeSession", "ssm:TerminateSession", "ssmmessages:OpenDataChannel"]
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:session/$${aws:userid}-*"
      },
      {
        Sid      = "ProtectAccessTag"
        Effect   = "Deny"
        Action   = ["ec2:CreateTags", "ec2:DeleteTags"]
        Resource = "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          "ForAnyValue:StringEquals" = { "aws:TagKeys" = ["automqVendor"] }
        }
      },
    ]
  })
}

output "ssm_operator_role_arn" {
  value = aws_iam_role.ssm_operator.arn
}
