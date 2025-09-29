variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs"
  type        = list(string)
}

variable "resource_depends_on" {
  description = "Resources that this module depends on"
  default     = null
}

variable "resource_suffix" {
  description = "Suffix for resource names"
  type        = string
}

variable "cluster_name" {
  description = "EKS Cluster name (overrides default naming)"
  type        = string
  default     = ""
}
