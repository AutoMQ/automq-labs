variable "console_endpoint" {
  description = "AutoMQ Console endpoint from the automq-console output"
  type        = string

  validation {
    condition     = can(regex("^https?://[^[:space:]]+$", var.console_endpoint))
    error_message = "console_endpoint must be a non-empty HTTP or HTTPS URL."
  }
}

variable "console_access_key" {
  description = "Local AutoMQ Console API access key from the automq-console output; this is not an AWS access key"
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.console_access_key)) > 0
    error_message = "console_access_key must not be empty."
  }
}

variable "console_secret_key" {
  description = "Local AutoMQ Console API secret key from the automq-console output; this is not an AWS secret key"
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.console_secret_key)) > 0
    error_message = "console_secret_key must not be empty."
  }
}

variable "environment_id" {
  description = "AutoMQ BYOC environment ID from the automq-console output"
  type        = string

  validation {
    condition     = length(trimspace(var.environment_id)) > 0
    error_message = "environment_id must not be empty."
  }
}

variable "instance_name" {
  description = "AutoMQ Kafka Instance name"
  type        = string
  default     = "automq-ec2-demo"

  validation {
    condition     = length(trimspace(var.instance_name)) > 0
    error_message = "instance_name must not be empty."
  }
}

variable "instance_description" {
  description = "AutoMQ Kafka Instance description"
  type        = string
  default     = "AutoMQ EC2 Custom example"
}

variable "automq_version" {
  description = "Exact AutoMQ data-plane version already available in the Console"
  type        = string
  default     = "5.5.3"

  validation {
    condition     = length(trimspace(var.automq_version)) > 0
    error_message = "automq_version must be an exact version available in the Console."
  }
}

variable "reserved_node_count" {
  description = "Number of EC2 broker nodes for the UsageBased instance"
  type        = number
  default     = 3
  nullable    = false

  validation {
    condition     = var.reserved_node_count >= 3 && var.reserved_node_count <= 100 && floor(var.reserved_node_count) == var.reserved_node_count
    error_message = "reserved_node_count must be an integer between three and 100."
  }
}

variable "broker_instance_type" {
  description = "EC2 instance type used by all UsageBased AutoMQ broker nodes"
  type        = string
  default     = "m7g.xlarge"

  validation {
    condition     = trimspace(var.broker_instance_type) != ""
    error_message = "broker_instance_type must not be empty."
  }
}

variable "private_subnet_ids_by_zone" {
  description = "Private broker subnet IDs keyed by availability zone; use the automq-console output"
  type        = map(list(string))

  validation {
    condition = (
      contains([1, 3], length(var.private_subnet_ids_by_zone)) &&
      alltrue([
        for zone, subnets in var.private_subnet_ids_by_zone :
        trimspace(zone) != "" && length(subnets) == 1 && try(trimspace(subnets[0]) != "", false)
      ])
    )
    error_message = "private_subnet_ids_by_zone must contain exactly one or three zones and exactly one non-empty subnet ID per zone."
  }
}

variable "data_bucket_name" {
  description = "S3 data bucket from the automq-console output"
  type        = string

  validation {
    condition     = length(trimspace(var.data_bucket_name)) > 0
    error_message = "data_bucket_name must be the non-empty bucket name from the automq-console output."
  }
}

variable "dns_zone_id" {
  description = "Private Route 53 hosted zone ID from the automq-console output"
  type        = string

  validation {
    condition     = length(trimspace(var.dns_zone_id)) > 0
    error_message = "dns_zone_id must not be empty."
  }
}

variable "instance_role_name" {
  description = "Dedicated AutoMQ data-plane IAM Role name from the automq-console output"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.instance_role_name))
    error_message = "instance_role_name must be a valid AWS IAM Role name, not an ARN."
  }
}

variable "wal_mode" {
  description = "Write-ahead log mode for the quick example"
  type        = string
  default     = "EBSWAL"

  validation {
    condition     = contains(["EBSWAL", "S3WAL"], upper(var.wal_mode))
    error_message = "wal_mode must be EBSWAL or S3WAL in this quick example."
  }
}

variable "instance_configs" {
  description = "Additional AutoMQ broker configuration"
  type        = map(string)
  default     = {}
}

variable "authentication_methods" {
  description = "Kafka authentication methods"
  type        = list(string)
  default     = ["anonymous"]
}

variable "transit_encryption_modes" {
  description = "Kafka transit encryption modes"
  type        = list(string)
  default     = ["plaintext"]
}

variable "data_encryption_mode" {
  description = "Data-at-rest encryption mode"
  type        = string
  default     = "NONE"
}

variable "schema_registry_enabled" {
  description = "Enable the AutoMQ Schema Registry"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the AutoMQ Instance"
  type        = map(string)
  default     = {}
}
