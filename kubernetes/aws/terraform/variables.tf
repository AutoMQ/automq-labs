
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
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
