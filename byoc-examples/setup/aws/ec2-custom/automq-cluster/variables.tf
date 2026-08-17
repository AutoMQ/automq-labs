variable "console_endpoint" {
  description = "AutoMQ Console endpoint from the automq-console output"
  type        = string

  validation {
    condition     = can(regex("^https?://[^[:space:]]+$", var.console_endpoint))
    error_message = "console_endpoint must be a non-empty HTTP or HTTPS URL."
  }
}

variable "console_access_key" {
  description = "AutoMQ Console access key from the automq-console output"
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.console_access_key)) > 0
    error_message = "console_access_key must not be empty."
  }
}

variable "console_secret_key" {
  description = "AutoMQ Console secret key from the automq-console output"
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

  validation {
    condition     = length(trimspace(var.automq_version)) > 0
    error_message = "automq_version must be an exact version available in the Console."
  }
}

variable "reserved_aku" {
  description = "Reserved AutoMQ Capacity Units"
  type        = number
  default     = 3
  nullable    = false

  validation {
    condition     = var.reserved_aku >= 3 && floor(var.reserved_aku) == var.reserved_aku
    error_message = "reserved_aku must be an integer greater than or equal to three."
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

variable "instance_role_arn" {
  description = "Dedicated AutoMQ data-plane IAM Role ARN from the automq-console output"
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)?:iam::[0-9]{12}:role/", var.instance_role_arn))
    error_message = "instance_role_arn must be an AWS IAM Role ARN, not a Role name or Instance Profile ARN."
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
