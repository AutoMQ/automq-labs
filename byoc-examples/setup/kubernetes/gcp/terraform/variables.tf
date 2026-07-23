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

variable "automq_config" {
  description = "Base64-encoded AutoMQ BYOC CONFIG value from the GCP installation configuration."
  type        = string
  sensitive   = true

  validation {
    condition = can(alltrue([
      for value in [
        jsondecode(base64decode(var.automq_config)).environmentId,
        jsondecode(base64decode(var.automq_config)).clientId,
        jsondecode(base64decode(var.automq_config)).clientSecret,
        jsondecode(base64decode(var.automq_config)).region,
        jsondecode(base64decode(var.automq_config)).opsBucket.bucketName,
      ] : trimspace(value) != ""
    ]))
    error_message = "automq_config must be valid base64 JSON containing environmentId, clientId, clientSecret, region, and opsBucket.bucketName."
  }
}

variable "automq_console_image" {
  description = "AutoMQ GCP Console container image from the installation configuration."
  type        = string

  validation {
    condition     = trimspace(var.automq_console_image) != ""
    error_message = "automq_console_image must not be empty."
  }
}

variable "automq_home_endpoint" {
  description = "AutoMQ Cloud endpoint used by the BYOC Console."
  type        = string
  default     = "https://console.automq.cloud"

  validation {
    condition     = can(regex("^https?://", var.automq_home_endpoint))
    error_message = "automq_home_endpoint must be an HTTP or HTTPS URL."
  }
}

variable "automq_console_registry" {
  description = "Optional credentials used to pull a private Console container image."
  type = object({
    server   = string
    username = string
    password = string
  })
  default = {
    server   = ""
    username = ""
    password = ""
  }
  sensitive = true

  validation {
    condition = (
      alltrue([for value in values(var.automq_console_registry) : trimspace(value) == ""]) ||
      alltrue([for value in values(var.automq_console_registry) : trimspace(value) != ""])
    )
    error_message = "automq_console_registry fields must either all be empty or all be set."
  }
}

variable "console_machine_type" {
  description = "GCE machine type used by the AutoMQ Console VM."
  type        = string
  default     = "e2-standard-2"

  validation {
    condition     = trimspace(var.console_machine_type) != ""
    error_message = "console_machine_type must not be empty."
  }
}

variable "console_ingress_source_ranges" {
  description = "IPv4 CIDR ranges allowed to access the AutoMQ Console on TCP port 8080."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition = (
      length(var.console_ingress_source_ranges) > 0 &&
      alltrue([
        for cidr in var.console_ingress_source_ranges :
        can(cidrhost(cidr, 0)) && can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/", cidr))
      ])
    )
    error_message = "console_ingress_source_ranges must contain at least one valid IPv4 CIDR."
  }
}
