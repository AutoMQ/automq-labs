# Required variables - must be specified in terraform.tfvars
variable "cluster_name" {
  description = "Name of the existing EKS cluster"
  type        = string
}

variable "existing_node_role_name" {
  description = "Name of the existing node group IAM role"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs where the node group will be deployed"
  type        = list(string)
}

variable "resource_suffix" {
  description = "Suffix to append to resource names for uniqueness"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# Node group configuration
variable "capacity_type" {
  description = "Type of capacity associated with the EKS Node Group. Valid values: ON_DEMAND, SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "instance_types" {
  description = "List of instance types for the node group - configured for at least 4c8g"
  type        = list(string)
  default     = ["c5.xlarge", "c5a.xlarge", "c5n.xlarge", "m5.xlarge", "m5a.xlarge"]
}

variable "desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 3
}

variable "min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "ami_type" {
  description = "Type of Amazon Machine Image (AMI) associated with the EKS Node Group"
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "disk_size" {
  description = "Disk size in GiB for worker nodes"
  type        = number
  default     = 50
}

# Optional configurations
variable "enable_dedicated_nodes" {
  description = "Whether to add taints to make nodes dedicated for load testing"
  type        = bool
  default     = false
}

variable "enable_remote_access" {
  description = "Whether to enable remote access to the nodes"
  type        = bool
  default     = false
}

variable "ec2_ssh_key" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
  default     = null
}

variable "source_security_group_ids" {
  description = "Security group IDs allowed for remote access"
  type        = list(string)
  default     = []
}

variable "additional_labels" {
  description = "Additional labels to apply to the node group"
  type        = map(string)
  default     = {}
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}