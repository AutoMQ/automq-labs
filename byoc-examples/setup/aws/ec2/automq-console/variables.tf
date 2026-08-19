variable "automq_config" {
  description = "Complete Base64-encoded AutoMQ BYOC CONFIG value from the AutoMQ Cloud installation wizard"
  type        = string
  sensitive   = true
  nullable    = false

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
  default     = "automq-ec2-quickstart"
  nullable    = false

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
  description = "IPv4 CIDR for the quick-start VPC; /16 through /20 creates valid AWS subnets after subdivision"
  type        = string
  default     = "10.42.0.0/16"
  nullable    = false

  validation {
    condition = (
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/(1[6-9]|20)$", var.vpc_cidr)) &&
      can(cidrhost(var.vpc_cidr, 0))
    )
    error_message = "vpc_cidr must be a valid IPv4 CIDR with a prefix length from /16 through /20."
  }
}

variable "console_image" {
  description = "AutoMQ BYOC Console container image"
  type        = string
  default     = "automq.azurecr.io/automq/automq-byoc-console:8.3.16-aws"
  nullable    = false

  validation {
    condition = (
      trimspace(var.console_image) != "" &&
      !can(regex("[[:space:]]", var.console_image))
    )
    error_message = "console_image must be a non-empty container image reference without whitespace."
  }
}

variable "console_instance_type" {
  description = "EC2 instance type for the AutoMQ Console"
  type        = string
  default     = "t3.large"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]+$", var.console_instance_type))
    error_message = "console_instance_type must be a valid EC2 instance type name."
  }
}

variable "console_allowed_cidr_blocks" {
  description = "IPv4 CIDRs allowed to access TCP 8080; null detects the Terraform caller's public IPv4 address"
  type        = list(string)
  default     = null

  validation {
    condition = var.console_allowed_cidr_blocks == null ? true : (
      length(var.console_allowed_cidr_blocks) > 0 && alltrue([
        for cidr in var.console_allowed_cidr_blocks :
        can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$", cidr)) &&
        can(cidrhost(cidr, 0))
      ])
    )
    error_message = "console_allowed_cidr_blocks must be null or contain at least one valid IPv4 CIDR."
  }
}

variable "data_bucket_name" {
  description = "Existing AutoMQ data bucket name; leave empty to create a module-managed bucket"
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition = var.data_bucket_name == "" ? true : (
      var.data_bucket_name == trimspace(var.data_bucket_name) &&
      length(var.data_bucket_name) >= 3 &&
      length(var.data_bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.data_bucket_name)) &&
      !strcontains(var.data_bucket_name, "..") &&
      !can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.data_bucket_name))
    )
    error_message = "data_bucket_name must be empty or a valid 3-63 character S3 bucket name."
  }
}

variable "force_destroy_data_bucket" {
  description = "Allow Terraform destroy to delete all objects from the module-created data bucket"
  type        = bool
  default     = true
  nullable    = false
}

variable "force_destroy_ops_bucket" {
  description = "Allow Terraform destroy to delete all objects from the module-created ops bucket"
  type        = bool
  default     = true
  nullable    = false
}

variable "tags" {
  description = "Additional tags applied to AWS resources"
  type        = map(string)
  default     = {}
  nullable    = false
}
