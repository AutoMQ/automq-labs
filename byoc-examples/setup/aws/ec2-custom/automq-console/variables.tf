variable "automq_config" {
  description = "Base64-encoded AutoMQ BYOC CONFIG value from the installation configuration"
  type        = string
  sensitive   = true

  validation {
    condition = can(alltrue([
      for value in [
        jsondecode(base64decode(var.automq_config)).environmentId,
        jsondecode(base64decode(var.automq_config)).clientId,
        jsondecode(base64decode(var.automq_config)).clientSecret,
        jsondecode(base64decode(var.automq_config)).region,
        jsondecode(base64decode(var.automq_config)).opsBucket.bucketName,
      ] : trimspace(value) != ""
    ]))
    error_message = "automq_config must be valid base64 JSON containing environmentId, clientId, clientSecret, region, and opsBucket.bucketName."
  }
}

variable "name_prefix" {
  description = "Short lowercase prefix used for AWS resource names"
  type        = string
  default     = "automq-ec2-demo"

  validation {
    condition = (
      length(var.name_prefix) >= 3 &&
      length(var.name_prefix) <= 24 &&
      can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.name_prefix))
    )
    error_message = "name_prefix must be 3-24 lowercase letters, numbers, or hyphens and cannot start or end with a hyphen."
  }
}

variable "vpc_cidr" {
  description = "CIDR for the demo VPC"
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrsubnet(var.vpc_cidr, 8, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR with room for /24 subnets."
  }
}

variable "console_image" {
  description = "AutoMQ BYOC Console container image"
  type        = string
  default     = "automq.azurecr.io/automq/automq-byoc-console:8.3.16-aws"

  validation {
    condition     = trimspace(var.console_image) != ""
    error_message = "console_image must not be empty."
  }
}

variable "console_instance_type" {
  description = "EC2 instance type for the AutoMQ Console"
  type        = string
  default     = "t3.large"
}

variable "console_allowed_cidr_blocks" {
  description = "IPv4 CIDRs allowed to access TCP 8080; null detects the Terraform caller's public IPv4 address"
  type        = list(string)
  default     = null

  validation {
    condition = var.console_allowed_cidr_blocks == null ? true : (
      length(var.console_allowed_cidr_blocks) > 0 && alltrue([
        for cidr in var.console_allowed_cidr_blocks : can(cidrhost(cidr, 0))
      ])
    )
    error_message = "console_allowed_cidr_blocks must be null or contain at least one valid IPv4 CIDR."
  }
}

variable "data_bucket_name" {
  description = "Existing AutoMQ data bucket; leave empty to create a disposable bucket"
  type        = string
  default     = ""
}

variable "force_destroy_data_bucket" {
  description = "Delete objects from the module-created data bucket during destroy"
  type        = bool
  default     = true
}

variable "force_destroy_ops_bucket" {
  description = "Delete objects from the module-created ops bucket during destroy"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags applied to AWS resources"
  type        = map(string)
  default     = {}
}
