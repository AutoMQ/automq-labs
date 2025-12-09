
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

resource "random_string" "resource_suffix" {
  length  = 4
  upper   = false
  lower   = true
  numeric = true
  special = false
}

locals {
  # Append a dash and a 4-char random tail to the configured suffix
  resource_suffix = "${var.resource_suffix}-${random_string.resource_suffix.result}"
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


# Producer Node Group Configuration
variable "enable_producer_nodes" {
  description = "Whether to create producer node group"
  type        = bool
  default     = true
}

# Producer node group scaling configuration
variable "producer_capacity_type" {
  description = "Type of capacity associated with the producer EKS Node Group. Valid values: ON_DEMAND, SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "producer_instance_types" {
  description = "List of instance types for the producer node group - configured for at least 4c8g"
  type        = list(string)
  default     = ["c5.xlarge", "c5a.xlarge", "c5n.xlarge", "m5.xlarge", "m5a.xlarge"]
}

variable "producer_desired_size" {
  description = "Desired number of producer nodes"
  type        = number
  default     = 1
}

variable "producer_max_size" {
  description = "Maximum number of producer nodes"
  type        = number
  default     = 2
}

variable "producer_min_size" {
  description = "Minimum number of producer nodes"
  type        = number
  default     = 1
}

variable "producer_ami_type" {
  description = "Type of Amazon Machine Image (AMI) associated with the producer EKS Node Group"
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "producer_disk_size" {
  description = "Disk size in GiB for producer worker nodes"
  type        = number
  default     = 50
}
