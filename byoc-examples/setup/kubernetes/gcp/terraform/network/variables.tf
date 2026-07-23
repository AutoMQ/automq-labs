variable "project_id" {
  description = "GCP project where network resources are created."
  type        = string
}

variable "region" {
  description = "GCP region for the subnets and Cloud NAT."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used to derive network resource names."
  type        = string
}

variable "network_cidrs" {
  description = "CIDR ranges for management, workload, Pods, and Services."
  type = object({
    management = string
    workload   = string
    pods       = string
    services   = string
  })
}
