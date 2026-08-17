variable "name_prefix" {
  description = "Unique resource name prefix for the AutoMQ data-plane role"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,46}$", var.name_prefix))
    error_message = "name_prefix must be 1-46 characters valid in an AWS IAM Role name."
  }
}

variable "data_bucket_name" {
  description = "S3 bucket used by AutoMQ data-plane storage"
  type        = string
  nullable    = false

  validation {
    condition = (
      length(var.data_bucket_name) >= 3 &&
      length(var.data_bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.data_bucket_name)) &&
      !strcontains(var.data_bucket_name, "..")
    )
    error_message = "data_bucket_name must be a valid 3-63 character S3 bucket name."
  }
}

variable "ops_bucket_name" {
  description = "S3 bucket used by AutoMQ operational artifacts"
  type        = string
  nullable    = false

  validation {
    condition = (
      length(var.ops_bucket_name) >= 3 &&
      length(var.ops_bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.ops_bucket_name)) &&
      !strcontains(var.ops_bucket_name, "..")
    )
    error_message = "ops_bucket_name must be a valid 3-63 character S3 bucket name."
  }
}

variable "hosted_zone_id" {
  description = "Private Route 53 hosted zone used by AutoMQ brokers"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.hosted_zone_id))
    error_message = "hosted_zone_id must be a valid Route 53 hosted zone ID beginning with Z."
  }
}

variable "tags" {
  description = "Tags applied to IAM resources"
  type        = map(string)
  default     = {}
  nullable    = false
}
