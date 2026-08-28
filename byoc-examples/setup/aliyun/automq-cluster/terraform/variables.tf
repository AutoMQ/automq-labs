variable "automq_byoc_endpoint" {
  description = "AutoMQ BYOC Control Plane endpoint."
  type        = string
}

variable "automq_byoc_access_key_id" {
  description = "Access Key ID of the AutoMQ Service Account."
  type        = string
  sensitive   = true
}

variable "automq_byoc_secret_key" {
  description = "Secret Access Key of the AutoMQ Service Account."
  type        = string
  sensitive   = true
}

variable "environment_id" {
  description = "Target AutoMQ BYOC environment ID."
  type        = string
}

variable "instance_name" {
  description = "Name of the AutoMQ Elastic Pool."
  type        = string
}

variable "instance_description" {
  description = "Description of the AutoMQ Elastic Pool."
  type        = string
}

variable "automq_version" {
  description = "AutoMQ data plane version. Use 5.5.2 or later for Regional ESSD cross-AZ failover."
  type        = string
}

variable "reserved_aku" {
  description = "Reserved AutoMQ Kafka Units for the Elastic Pool."
  type        = number

  validation {
    condition     = var.reserved_aku >= 3
    error_message = "reserved_aku must be at least 3."
  }
}

variable "pricing_mode" {
  description = "AutoMQ billing mode. This VMIS Elastic Pool example uses SubscriptionBased."
  type        = string

  validation {
    condition     = var.pricing_mode == "SubscriptionBased"
    error_message = "pricing_mode must be SubscriptionBased for this example."
  }
}

variable "networks" {
  description = "Exactly three Alibaba Cloud availability zones, each with one existing VSwitch/subnet."
  type = list(object({
    zone    = string
    subnets = list(string)
  }))

  validation {
    condition = (
      length(var.networks) == 3 &&
      length(distinct([for network in var.networks : network.zone])) == 3 &&
      alltrue([
        for network in var.networks :
        trimspace(network.zone) != "" &&
        length(network.subnets) == 1 &&
        trimspace(network.subnets[0]) != ""
      ])
    )
    error_message = "networks must contain three distinct zones with exactly one non-empty VSwitch/subnet ID per zone."
  }
}

variable "security_group_ids" {
  description = "Existing Alibaba Cloud security group IDs for the Elastic Pool."
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) > 0 && alltrue([for id in var.security_group_ids : trimspace(id) != ""])
    error_message = "security_group_ids must contain at least one non-empty security group ID."
  }
}

variable "data_buckets" {
  description = "The existing Alibaba Cloud OSS data bucket used by the Elastic Pool."
  type = list(object({
    bucket_name = string
  }))

  validation {
    condition = (
      length(var.data_buckets) == 1 &&
      trimspace(var.data_buckets[0].bucket_name) != ""
    )
    error_message = "data_buckets must contain exactly one existing non-empty OSS bucket name."
  }
}

variable "dns_zone_id" {
  description = "ID of the existing Alibaba Cloud PrivateZone."
  type        = string
}

variable "ram_role_name" {
  description = "Name of the existing Alibaba Cloud data-plane RAM role."
  type        = string
}

variable "tags" {
  description = "Exactly two custom tags applied to the Elastic Pool resources."
  type        = map(string)

  validation {
    condition = (
      length(var.tags) == 2 &&
      alltrue([for key, value in var.tags : trimspace(key) != "" && trimspace(value) != ""])
    )
    error_message = "tags must contain exactly two non-empty custom tag key-value pairs."
  }
}
