
variable "region" {
  description = "AWS region"
  type        = string
}

variable "resource_suffix" {
  description = "Suffix for resource names"
  type        = string
}

variable "karpenter_discovery_tag" {
  description = "Value for karpenter.sh/discovery tag. If set, subnets will be tagged for Karpenter discovery."
  type        = string
  default     = ""
}
