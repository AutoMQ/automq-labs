# Random suffix for unique naming when no explicit env is provided
resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

variable "env" {
  description = "Friendly identifier for this BYOC environment. If omitted a random suffix is used."
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS region"
  type        = string
  validation {
    condition     = length(trimspace(var.region)) > 0
    error_message = "region must be provided"
  }
}

variable "image_name" {
  description = "Name filter for the AMI used by the console instance"
  type        = string
  validation {
    condition     = length(trimspace(var.image_name)) > 0
    error_message = "image_name must be provided"
  }
}

variable "vpc_id" {
  description = "Existing VPC ID to deploy resources into"
  type        = string
  validation {
    condition     = length(trimspace(var.vpc_id)) > 0
    error_message = "vpc_id must reference an existing VPC"
  }
}

variable "public_subnet_id" {
  description = "Public subnet ID for the console instance"
  type        = string
  validation {
    condition     = length(trimspace(var.public_subnet_id)) > 0
    error_message = "public_subnet_id cannot be empty"
  }
}

variable "data_bucket_name" {
  description = "Existing S3 bucket name to use for AutoMQ data. Leave empty to create a managed bucket."
  type        = string
  default     = ""
}

variable "ops_bucket_name" {
  description = "Existing S3 bucket name to use for AutoMQ ops artifacts. Leave empty to create a managed bucket."
  type        = string
  default     = ""
}

variable "automq_byoc_ec2_instance_type" {
  description = "EC2 instance type for the AutoMQ console"
  type        = string
  default     = "t3.large"
}

locals {
  resolved_env_base  = length(trimspace(var.env)) > 0 ? trimspace(var.env) : "automq-byoc-env"
  normalized_env     = replace(lower(local.resolved_env_base), "[^a-z0-9-]", "-")
  name_suffix        = "${local.normalized_env}-${random_string.suffix.result}"
  env_id             = local.normalized_env
  data_bucket_name   = length(trimspace(var.data_bucket_name)) > 0 ? var.data_bucket_name : "automq-data-${var.region}-${local.env_id}"
  ops_bucket_name    = length(trimspace(var.ops_bucket_name)) > 0 ? var.ops_bucket_name : "automq-ops-${var.region}-${local.env_id}"
  create_data_bucket = length(trimspace(var.data_bucket_name)) == 0
  create_ops_bucket  = length(trimspace(var.ops_bucket_name)) == 0
  common_tags = {
    Terraform           = "true"
    automqEnvironmentID = local.env_id
  }
}