variable "name_prefix" {
  description = "Short lowercase prefix used for AWS resource names"
  type        = string

  validation {
    condition = (
      length(var.name_prefix) >= 3 &&
      length(var.name_prefix) <= 24 &&
      can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.name_prefix))
    )
    error_message = "name_prefix must be 3-24 lowercase letters, numbers, or hyphens and cannot start or end with a hyphen."
  }
}

variable "region" {
  description = "AWS region containing the VPC, subnets, buckets, and Console AMI"
  type        = string

  validation {
    condition     = length(trimspace(var.region)) > 0
    error_message = "region must not be empty."
  }
}

variable "environment_id" {
  description = "AutoMQ BYOC environment ID from the Installation Script"
  type        = string

  validation {
    condition     = length(trimspace(var.environment_id)) > 0
    error_message = "environment_id must not be empty."
  }
}

variable "client_id" {
  description = "AutoMQ BYOC client ID from the Installation Script"
  type        = string

  validation {
    condition     = length(trimspace(var.client_id)) > 0
    error_message = "client_id must not be empty."
  }
}

variable "client_secret" {
  description = "AutoMQ BYOC client secret from the Installation Script"
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.client_secret)) > 0
    error_message = "client_secret must not be empty."
  }
}

variable "ops_bucket_name" {
  description = "Existing ops bucket from the AutoMQ BYOC Installation Script"
  type        = string

  validation {
    condition     = length(trimspace(var.ops_bucket_name)) > 0
    error_message = "ops_bucket_name must not be empty."
  }
}

variable "data_bucket_name" {
  description = "Existing AutoMQ data bucket; leave empty to create a disposable bucket"
  type        = string
  default     = ""
}

variable "force_destroy_data_bucket" {
  description = "Delete objects from a module-created data bucket during destroy; intended only for demos"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "Existing VPC ID"
  type        = string
}

variable "public_subnet_id" {
  description = "Existing public subnet for the AutoMQ Console EC2 instance"
  type        = string
}

variable "private_subnet_ids_by_zone" {
  description = "Private broker subnet IDs keyed by availability zone"
  type        = map(list(string))

  validation {
    condition = (
      contains([1, 3], length(var.private_subnet_ids_by_zone)) &&
      alltrue([
        for zone, subnets in var.private_subnet_ids_by_zone :
        trimspace(zone) != "" && length(subnets) == 1 && try(trimspace(subnets[0]) != "", false)
      ])
    )
    error_message = "private_subnet_ids_by_zone must contain exactly one or three zones and exactly one non-empty subnet ID per zone."
  }
}

variable "console_ami_name" {
  description = "Exact AutoMQ Console AMI name available in the selected region"
  type        = string

  validation {
    condition     = length(trimspace(var.console_ami_name)) > 0
    error_message = "console_ami_name must not be empty."
  }
}

variable "console_ami_owners" {
  description = "AWS account IDs allowed to own the Console AMI; use self for an AMI built in this account"
  type        = list(string)

  validation {
    condition     = length(var.console_ami_owners) > 0 && alltrue([for owner in var.console_ami_owners : trimspace(owner) != ""])
    error_message = "console_ami_owners must contain at least one AWS account ID or self."
  }
}

variable "console_instance_type" {
  description = "EC2 instance type for the AutoMQ Console"
  type        = string
  default     = "t3.large"
}

variable "console_allowed_cidr_blocks" {
  description = "IPv4 CIDRs allowed to access the Console on TCP 8080"
  type        = list(string)

  validation {
    condition     = length(var.console_allowed_cidr_blocks) > 0 && alltrue([for cidr in var.console_allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "console_allowed_cidr_blocks must contain at least one valid IPv4 CIDR."
  }
}

variable "ssh_allowed_cidr_blocks" {
  description = "IPv4 CIDRs allowed to access the Console host on TCP 22"
  type        = list(string)

  validation {
    condition     = length(var.ssh_allowed_cidr_blocks) > 0 && alltrue([for cidr in var.ssh_allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ssh_allowed_cidr_blocks must contain at least one valid IPv4 CIDR."
  }
}

variable "private_key_directory" {
  description = "Local directory in which Terraform writes the generated Console SSH private key"
  type        = string
  default     = "~/.ssh"
}

variable "tags" {
  description = "Additional tags applied to AWS resources"
  type        = map(string)
  default     = {}
}
