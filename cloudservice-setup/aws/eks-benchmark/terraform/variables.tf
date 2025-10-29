
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


# Benchmark Node Group Configuration
variable "enable_benchmark_nodes" {
  description = "Whether to create benchmark node group"
  type        = bool
  default     = true
}

variable "benchmark_node_role_name" {
  description = "Name of the existing node group IAM role for benchmark nodes"
  type        = string
  default     = ""
}

variable "benchmark_subnet_ids" {
  description = "List of subnet IDs where the benchmark node group will be deployed"
  type        = list(string)
  default     = []
}

# Benchmark node group scaling configuration
variable "benchmark_capacity_type" {
  description = "Type of capacity associated with the benchmark EKS Node Group. Valid values: ON_DEMAND, SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "benchmark_instance_types" {
  description = "List of instance types for the benchmark node group - configured for at least 4c8g"
  type        = list(string)
  default     = ["c5.xlarge", "c5a.xlarge", "c5n.xlarge", "m5.xlarge", "m5a.xlarge"]
}

variable "benchmark_desired_size" {
  description = "Desired number of benchmark nodes"
  type        = number
  default     = 2
}

variable "benchmark_max_size" {
  description = "Maximum number of benchmark nodes"
  type        = number
  default     = 3
}

variable "benchmark_min_size" {
  description = "Minimum number of benchmark nodes"
  type        = number
  default     = 1
}

variable "benchmark_ami_type" {
  description = "Type of Amazon Machine Image (AMI) associated with the benchmark EKS Node Group"
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "benchmark_disk_size" {
  description = "Disk size in GiB for benchmark worker nodes"
  type        = number
  default     = 50
}

# Optional benchmark configurations
variable "benchmark_enable_dedicated_nodes" {
  description = "Whether to add taints to make benchmark nodes dedicated for load testing"
  type        = bool
  default     = true
}

# Prometheus Configuration
variable "enable_prometheus" {
  description = "Whether to deploy Prometheus monitoring stack"
  type        = bool
  default     = true
}

variable "prometheus_namespace" {
  description = "Kubernetes namespace for Prometheus deployment"
  type        = string
  default     = "monitoring"
}

variable "prometheus_chart_version" {
  description = "Version of the kube-prometheus-stack Helm chart"
  type        = string
  default     = "61.3.0"
}

variable "prometheus_storage_class" {
  description = "StorageClass name used for Prometheus PVCs"
  type        = string
  default     = "gp2"
}