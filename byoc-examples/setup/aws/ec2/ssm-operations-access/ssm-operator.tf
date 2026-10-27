terraform {
  required_version = ">= 1.5.7, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }
}

variable "aws_region" {
  description = "Region containing the approved EC2 instances"
  type        = string

  validation {
    condition     = length(trimspace(var.aws_region)) > 0
    error_message = "aws_region must not be empty."
  }
}

variable "operator_role_name" {
  description = "Name of the customer-owned role assumed by AutoMQ operators"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.operator_role_name))
    error_message = "operator_role_name must be a valid IAM role name."
  }
}

variable "automq_principal_arn" {
  description = "Exact AutoMQ IAM role allowed to assume the customer-owned role"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+", var.automq_principal_arn))
    error_message = "automq_principal_arn must be an IAM role ARN."
  }
}

variable "external_id" {
  description = "Customer-specific External ID agreed with AutoMQ"
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.external_id)) > 0
    error_message = "external_id must not be empty."
  }
}

variable "target_instance_ids" {
  description = "EC2 instances that AutoMQ operators may access when tagged automqVendor=automq"
  type        = set(string)

  validation {
    condition = length(var.target_instance_ids) > 0 && alltrue([
      for id in var.target_instance_ids : can(regex("^i-([0-9a-f]{8}|[0-9a-f]{17})$", id))
    ])
    error_message = "target_instance_ids must contain at least one valid EC2 instance ID."
  }
}

variable "additional_instance_role_names" {
  description = "Instance roles that still need AmazonSSMManagedInstanceCore, such as the Cluster role; omit the already managed Console role"
  type        = set(string)
  default     = []
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "ssm_operator" {
  name = var.operator_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = var.automq_principal_arn }
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
        Sid      = "StartSessionOnApprovedInstances"
        Effect   = "Allow"
        Action   = "ssm:StartSession"
        Resource = [for id in var.target_instance_ids : "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/${id}"]
        Condition = {
          StringEquals = { "ssm:resourceTag/automqVendor" = "automq" }
        }
      },
      {
        Sid      = "UseShellDocument"
        Effect   = "Allow"
        Action   = "ssm:StartSession"
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:document/SSM-SessionManagerRunShell"
      },
      {
        Sid      = "ManageOwnSessions"
        Effect   = "Allow"
        Action   = ["ssm:ResumeSession", "ssm:TerminateSession", "ssmmessages:OpenDataChannel"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:session/$${aws:userid}-*"
      },
      {
        Sid      = "ProtectAccessTag"
        Effect   = "Deny"
        Action   = ["ec2:CreateTags", "ec2:DeleteTags"]
        Resource = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          "ForAnyValue:StringEquals" = { "aws:TagKeys" = ["automqVendor"] }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_agent" {
  for_each = var.additional_instance_role_names

  role       = each.value
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

output "ssm_operator_role_arn" {
  description = "Customer role ARN to give AutoMQ for short-lived SSM access"
  value       = aws_iam_role.ssm_operator.arn
}
