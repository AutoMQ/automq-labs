variable "kubernetes_cluster_id" {
  description = "Existing GKE resource ID: projects/<project>/locations/<region-or-zone>/clusters/<name>. The cluster must be in the Console's project, Region, and VPC."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^projects/[^/[:space:]]+/locations/[^/[:space:]]+/clusters/[a-z]([-a-z0-9]*[a-z0-9])?$", var.kubernetes_cluster_id))
    error_message = "kubernetes_cluster_id must be a full GKE resource ID, not a cluster name or URL."
  }
}

variable "console_state_path" {
  description = "Path to the existing GCP Console's local Terraform state, relative to this directory or absolute."
  type        = string
  default     = "../terraform/terraform.tfstate"
  nullable    = false

  validation {
    condition     = trimspace(var.console_state_path) != ""
    error_message = "console_state_path must not be empty."
  }
}

variable "kafka_state_path" {
  description = "Path to the existing AutoMQ Instance's local Terraform state, relative to this directory or absolute."
  type        = string
  default     = "../automq-cluster/terraform/terraform.tfstate"
  nullable    = false

  validation {
    condition     = trimspace(var.kafka_state_path) != ""
    error_message = "kafka_state_path must not be empty."
  }
}

variable "console_endpoint_override" {
  description = "Optional reachable Console HTTP(S) URL; null uses the Console state output."
  type        = string
  default     = null

  validation {
    condition     = var.console_endpoint_override == null ? true : can(regex("^https?://[^[:space:]]+$", var.console_endpoint_override))
    error_message = "console_endpoint_override must be null or an HTTP(S) URL."
  }
}

variable "connect_node_pool_name" {
  description = "Existing GKE node pool for Connect workers. It must have spare capacity and use the GKE metadata server."
  type        = string
  default     = "default-pool"
  nullable    = false

  validation {
    condition     = length(var.connect_node_pool_name) <= 40 && can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.connect_node_pool_name))
    error_message = "connect_node_pool_name must be a valid GKE node pool name of at most 40 characters."
  }
}

variable "connect_cluster_name" {
  description = "Name for this demo's Connect Cluster and derived GCP resources."
  type        = string
  default     = "gcp-mysql-connect-demo"
  nullable    = false

  validation {
    condition     = length(var.connect_cluster_name) >= 3 && length(var.connect_cluster_name) <= 40 && can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.connect_cluster_name))
    error_message = "connect_cluster_name must contain 3-40 lowercase letters, numbers, or hyphens, start with a letter, and end with a letter or number."
  }
}

variable "connect_namespace" {
  description = "Dedicated Kubernetes namespace created and owned by this example."
  type        = string
  default     = "automq-connect"
  nullable    = false

  validation {
    condition     = length(var.connect_namespace) <= 63 && !contains(["default", "kube-system", "kube-public", "kube-node-lease"], var.connect_namespace) && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.connect_namespace))
    error_message = "connect_namespace must be a dedicated, non-system namespace with a valid DNS label name."
  }
}

variable "connect_service_account" {
  description = "Kubernetes ServiceAccount created in connect_namespace and linked to the worker Google Service Account."
  type        = string
  default     = "automq-connect"
  nullable    = false

  validation {
    condition     = length(var.connect_service_account) <= 63 && var.connect_service_account != "default" && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.connect_service_account))
    error_message = "connect_service_account must be a dedicated DNS label name of at most 63 characters, other than default."
  }
}

variable "worker_service_account_id" {
  description = "Optional Google Service Account ID, not an email. Null derives a name from connect_cluster_name."
  type        = string
  default     = null

  validation {
    condition     = var.worker_service_account_id == null ? true : can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.worker_service_account_id))
    error_message = "worker_service_account_id must be null or a 6-30 character Google Service Account ID."
  }
}

variable "connect_tolerations" {
  description = "Tolerations for the selected existing node pool. An empty list is omitted from the API request; the default system pool normally needs none."
  type = list(object({
    key      = string
    operator = optional(string, "Equal")
    value    = optional(string, "")
    effect   = optional(string, "NoSchedule")
  }))
  default  = []
  nullable = false

  validation {
    condition = alltrue([
      for toleration in var.connect_tolerations :
      trimspace(toleration.key) != "" &&
      contains(["Equal", "Exists"], toleration.operator) &&
      contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], toleration.effect) &&
      (toleration.operator != "Exists" || toleration.value == "")
    ])
    error_message = "Each toleration needs a key, operator Equal or Exists, and a Kubernetes effect. Exists must not set a value."
  }
}

variable "worker_count" {
  description = "Provisioned Connect worker count; this does not resize the external GKE node pool."
  type        = number
  default     = 1
  nullable    = false

  validation {
    condition     = var.worker_count >= 1 && floor(var.worker_count) == var.worker_count
    error_message = "worker_count must be a positive integer."
  }
}

variable "worker_resource_spec" {
  description = "AutoMQ Connect worker resource tier."
  type        = string
  default     = "TIER1"
  nullable    = false

  validation {
    condition     = contains(["TIER1", "TIER2", "TIER3", "TIER4"], var.worker_resource_spec)
    error_message = "worker_resource_spec must be TIER1, TIER2, TIER3, or TIER4."
  }
}

variable "connect_version" {
  description = "Optional Connect worker version from the Console catalog. Null selects the backend default; this is not the Broker or Console image version."
  type        = string
  default     = null

  validation {
    condition     = var.connect_version == null ? true : trimspace(var.connect_version) != ""
    error_message = "connect_version must be null or a non-empty Connect worker version."
  }
}

variable "tags" {
  description = "Tags for the AutoMQ Connect Cluster."
  type        = map(string)
  default     = { purpose = "demo" }
  nullable    = false
}
