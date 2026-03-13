# Basic Variables
variable "region" {
  description = "TencentCloud region to deploy to (e.g. ap-guangzhou)"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the existing VPC to use."
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones. Must provide 1 or 3 availability zones."
  type        = list(string)
  validation {
    condition     = length(var.availability_zones) == 1 || length(var.availability_zones) == 3
    error_message = "Must provide exactly 1 or 3 availability zones."
  }
}

variable "subnet_ids" {
  description = "List of subnet IDs corresponding to the availability zones. Must match the length of availability_zones (1 or 3)."
  type        = list(string)
  validation {
    condition     = length(var.subnet_ids) == 1 || length(var.subnet_ids) == 3
    error_message = "Must provide exactly 1 or 3 subnet IDs."
  }
}

variable "public_instance_type" {
  description = "Instance type for the public node pool."
  type        = string
  default     = "SA9.MEDIUM4"
}

variable "tke_cluster_name" {
  description = "TKE Cluster Name."
  type        = string
}

variable "tke_cluster_version" {
  description = "Kubernetes version for the TKE cluster."
  type        = string
  default     = "1.32.2"
}

variable "node_os" {
  description = "OS image ID for node pool instances."
  type        = string
  default     = "img-eb30mz89"
}

variable "instance_type" {
  description = "Instance type for AutoMQ dedicated node pool."
  type        = string
  default     = "SA5.LARGE16"
}

variable "instance_charge_type" {
  description = "CVM instance charge type for node pools. Valid values: POSTPAID_BY_HOUR (pay-as-you-go), SPOTPAID (spot)."
  type        = string
  default     = "POSTPAID_BY_HOUR"
  validation {
    condition     = contains(["POSTPAID_BY_HOUR", "SPOTPAID"], var.instance_charge_type)
    error_message = "instance_charge_type must be either POSTPAID_BY_HOUR or SPOTPAID."
  }
}

variable "spot_max_price" {
  description = "Max price for spot instances (per hour). Only used when instance_charge_type is SPOTPAID. Set to a high value to use market price."
  type        = string
  default     = "1000"
}

variable "key_ids" {
  description = "List of SSH key IDs for node pool instances. Must provide at least one."
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for node pool instances."
  type        = list(string)
}

# Service CIDR for VPC-CNI mode
variable "service_cidr" {
  description = "Service CIDR for the TKE cluster. Must be in 10./192.168/172.[16-31] segments."
  type        = string
  default     = "192.168.128.0/20"
}

# CAM policy file path
variable "cam_policy_file" {
  description = "Path to the CAM policy JSON file to attach to the node role."
  type        = string
  default     = "cam-policy.json"
}

# Tags
variable "common_tags" {
  description = "Additional tags for merging with common tags."
  type        = map(string)
  default     = {}
}
