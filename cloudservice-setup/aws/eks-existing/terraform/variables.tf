# Basic Configuration
variable "region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "resource_suffix" {
  description = "Suffix for resource names to ensure uniqueness"
  type        = string
  default     = "automqlab"
}

# Network Configuration
variable "vpc_id" {
  description = "VPC ID for the existing EKS cluster"
  type        = string

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "VPC ID must be a valid VPC identifier starting with 'vpc-'."
  }
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the EKS Node Group"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 1
    error_message = "At least one private subnet ID must be provided."
  }
}

variable "console_subnet_id" {
  description = "Public subnet ID for the AutoMQ Console deployment"
  type        = string

  validation {
    condition     = can(regex("^subnet-", var.console_subnet_id))
    error_message = "Console subnet ID must be a valid subnet identifier starting with 'subnet-'."
  }
}

# EKS Configuration
variable "eks_cluster_name" {
  description = "Name of the existing EKS cluster to configure"
  type        = string
}

# EKS Add-ons Configuration
variable "enable_autoscaler" {
  description = "Enable the Kubernetes Cluster Autoscaler addon"
  type        = bool
  default     = true
}

variable "enable_alb_ingress_controller" {
  description = "Enable the AWS Load Balancer Controller addon"
  type        = bool
  default     = true
}

variable "enable_vpc_cni" {
  description = "Enable the AWS VPC CNI addon"
  type        = bool
  default     = true
}

variable "enable_ebs_csi_driver" {
  description = "Enable the AWS EBS CSI driver addon"
  type        = bool
  default     = true
}

# Node Group Configuration
variable "node_group" {
  description = "Configuration for the AutoMQ dedicated EKS node group"
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
    ami_type      = "AL2_ARM_64"  # Amazon Linux 2 ARM64 AMI for Graviton2 instances
  }

  validation {
    condition     = var.node_group.min_size <= var.node_group.desired_size && var.node_group.desired_size <= var.node_group.max_size
    error_message = "Node group sizing must follow: min_size <= desired_size <= max_size."
  }

  validation {
    condition     = var.node_group.min_size >= 1
    error_message = "Node group min_size must be at least 1."
  }
}