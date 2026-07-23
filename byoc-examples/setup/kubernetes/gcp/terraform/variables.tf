variable "project_id" {
  description = "GCP project where the network and GKE cluster are created."
  type        = string

  validation {
    condition     = trimspace(var.project_id) != ""
    error_message = "project_id must not be empty."
  }
}

variable "region" {
  description = "GCP region for the regional GKE cluster."
  type        = string

  validation {
    condition     = trimspace(var.region) != ""
    error_message = "region must not be empty."
  }
}

variable "zones" {
  description = "Three zones in the selected region used by the default and AutoMQ node pools."
  type        = list(string)

  validation {
    condition     = length(var.zones) == 3 && length(distinct(var.zones)) == 3 && alltrue([for zone in var.zones : trimspace(zone) != ""])
    error_message = "zones must contain exactly three distinct, non-empty zones."
  }
}

variable "name_prefix" {
  description = "Prefix used to derive the names of all resources."
  type        = string
  default     = "automq"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.name_prefix)) && length(var.name_prefix) <= 33
    error_message = "name_prefix must use lowercase letters, numbers, or hyphens, start with a letter, end with a letter or number, and contain at most 33 characters."
  }
}

variable "network_cidrs" {
  description = "CIDR ranges for the management subnet, workload subnet, GKE Pods, and GKE Services."
  type = object({
    management = string
    workload   = string
    pods       = string
    services   = string
  })
  default = {
    management = "10.10.0.0/24"
    workload   = "10.20.0.0/20"
    pods       = "10.30.0.0/16"
    services   = "10.40.0.0/20"
  }

  validation {
    condition = alltrue([
      for cidr in values(var.network_cidrs) :
      can(cidrhost(cidr, 0)) && can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/", cidr))
    ])
    error_message = "Every network_cidrs value must be a valid IPv4 CIDR."
  }
}

variable "automq_node_pool" {
  description = "Capacity settings for the dedicated AutoMQ workload node pool."
  type = object({
    machine_type = string
    min_size     = number
    max_size     = number
  })
  default = {
    machine_type = "n2d-standard-4"
    min_size     = 3
    max_size     = 10
  }

  validation {
    condition = (
      trimspace(var.automq_node_pool.machine_type) != "" &&
      var.automq_node_pool.min_size >= 3 &&
      var.automq_node_pool.max_size >= var.automq_node_pool.min_size
    )
    error_message = "automq_node_pool requires a non-empty machine_type, min_size of at least 3, and max_size greater than or equal to min_size."
  }
}
