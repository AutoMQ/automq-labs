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

variable "availability_zones" {
  description = "Availability zones to use. If empty, discover the first three zones in the region."
  type        = list(string)
  default     = []
}

variable "automq_node_pool" {
  description = "Configuration for the AutoMQ workload node pool"
  type = object({
    instance_type    = string
    min_size         = number
    max_size         = number
    desired_capacity = number
    spot             = bool
    spot_max_price   = optional(string, "1000")
  })
  default = {
    instance_type    = "SA5.LARGE16"
    min_size         = 3
    max_size         = 5
    desired_capacity = 4
    spot             = true
    spot_max_price   = "1000"
  }
}
