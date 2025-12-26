
variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "resource_suffix" {
  description = "Suffix for resource names"
  type        = string
  default     = "automqlab"
}

variable "node_group" {
  description = "Configuration for EKS node group"
  type = object({
    name          = string
    ami_type      = string
    instance_type = string
    desired_size  = number
    max_size      = number
    min_size      = number
  })
  default = {
    name          = "automq-node-group"
    desired_size  = 4             # Desired number of nodes
    max_size      = 10            # Maximum number of nodes
    min_size      = 3             # Minimum number of nodes
    instance_type = "c6g.2xlarge" # Compute-optimized instance with AWS Graviton2 processor
    ami_type      = "AL2_ARM_64"  # Amazon Linux 2 AMI type, can use AL2_ARM_64 for ARM architecture
  }
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

variable "create_nat_gateway" {
  description = "Whether to create NAT Gateway for existing VPC (only applicable when use_existing_vpc is true). Requires existing_public_subnet_ids to be provided."
  type        = bool
  default     = false
}
