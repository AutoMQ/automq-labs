
variable "region" {
  description = "AWS region"
  type        = string
}

variable "resource_suffix" {
  description = "Suffix for resource names"
  type        = string
}

variable "use_existing_vpc" {
  description = "Whether to use an existing VPC instead of creating a new one"
  type        = bool
  default     = false
}

variable "existing_vpc_id" {
  description = "ID of existing VPC to use (required if use_existing_vpc is true)"
  type        = string
  default     = ""
}

variable "existing_private_subnet_ids" {
  description = "List of existing private subnet IDs to use (required if use_existing_vpc is true)"
  type        = list(string)
  default     = []
}

variable "existing_public_subnet_ids" {
  description = "List of existing public subnet IDs to use (optional if use_existing_vpc is true)"
  type        = list(string)
  default     = []
}
