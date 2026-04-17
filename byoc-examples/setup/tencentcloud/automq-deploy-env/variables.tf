variable "alias" {
  description = "Environment alias (e.g., dev)"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "Tencent Cloud region to deploy the environment"
  type        = string
  default     = "ap-shanghai"
}

variable "vpc_id" {
  description = "ID of an existing VPC to deploy into"
  type        = string
}

variable "subnet_ids" {
  description = "List of existing subnet IDs (across different AZs) for TKE node pools and VPC-CNI ENI allocation"
  type        = list(string)
}

variable "enable_cluster_internet" {
  description = "Whether to enable public internet access for the TKE API server"
  type        = bool
  default     = false
}

variable "automq_node_pool" {
  description = "Configuration for the AutoMQ workload node pool"
  type = object({
    instance_type              = string
    min_size                   = number
    max_size                   = number
    desired_capacity           = number
    instance_charge_type       = optional(string, "SPOTPAID")       # SPOTPAID | POSTPAID_BY_HOUR | PREPAID
    spot_max_price             = optional(string, "1000")           # Only used when instance_charge_type = SPOTPAID
    prepaid_period             = optional(number, 1)                # Subscription months (1,2,3,4,5,6,7,8,9,10,11,12,24,36). Only used when PREPAID.
    prepaid_renew_flag         = optional(string, "NOTIFY_AND_AUTO_RENEW") # NOTIFY_AND_AUTO_RENEW | NOTIFY_AND_MANUAL_RENEW | DISABLE_NOTIFY_AND_MANUAL_RENEW
  })
  default = {
    instance_type              = "SA5.LARGE16"
    min_size                   = 3
    max_size                   = 5
    desired_capacity           = 4
    instance_charge_type       = "SPOTPAID"
    spot_max_price             = "1000"
    prepaid_period             = 1
    prepaid_renew_flag         = "NOTIFY_AND_AUTO_RENEW"
  }
}
