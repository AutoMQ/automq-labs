variable "region" {
  description = "AWS region containing the three selected availability zones."
  type        = string
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.region))
    error_message = "region must be an AWS region name."
  }
}

variable "availability_zones" {
  description = "Exactly three distinct availability zone names in region."
  type        = list(string)
  validation {
    condition     = length(var.availability_zones) == 3 && length(distinct(var.availability_zones)) == 3 && alltrue([for az in var.availability_zones : startswith(az, var.region) && can(regex("[a-z]$", az))])
    error_message = "availability_zones must contain three distinct AZ names in region."
  }
}

variable "name_prefix" {
  description = "Unique lowercase prefix for this disposable evaluation network."
  type        = string
  default     = "automq-eks-demo"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,29}$", var.name_prefix))
    error_message = "name_prefix must be 3-30 lowercase letters, digits, or hyphens and start with a letter."
  }
}

variable "vpc_cidr" {
  description = "Evaluation VPC IPv4 range; ensure it does not overlap connected networks."
  type        = string
  default     = "10.42.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && can(regex("/(1[6-9]|20)$", var.vpc_cidr))
    error_message = "vpc_cidr must be an IPv4 CIDR with a /16 through /20 prefix."
  }
}
