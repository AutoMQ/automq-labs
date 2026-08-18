variable "console_endpoint" {
  description = "AutoMQ Console endpoint from the automq-console output"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^https?://[^[:space:]]+$", var.console_endpoint))
    error_message = "console_endpoint must be a non-empty HTTP or HTTPS URL."
  }
}

variable "console_access_key" {
  description = "Local AutoMQ Console API access key from the automq-console output; this is not an AWS access key"
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(trimspace(var.console_access_key)) > 0
    error_message = "console_access_key must not be empty."
  }
}

variable "console_secret_key" {
  description = "Local AutoMQ Console API secret key from the automq-console output; this is not an AWS secret key"
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(trimspace(var.console_secret_key)) > 0
    error_message = "console_secret_key must not be empty."
  }
}

variable "environment_id" {
  description = "AutoMQ BYOC environment ID from the automq-console output"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^env-[A-Za-z0-9]+$", var.environment_id))
    error_message = "environment_id must use the AutoMQ environment ID format env-<identifier>."
  }
}

variable "instance_name" {
  description = "AutoMQ Kafka Instance name"
  type        = string
  default     = "automq-ec2-quickstart"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{3,64}$", var.instance_name))
    error_message = "instance_name must be 3-64 letters, numbers, underscores, or hyphens."
  }
}

variable "instance_description" {
  description = "AutoMQ Kafka Instance description"
  type        = string
  default     = "AutoMQ EC2 quick-start instance"
  nullable    = false

  validation {
    condition     = length(trimspace(var.instance_description)) >= 3 && length(var.instance_description) <= 256
    error_message = "instance_description must contain 3-256 characters."
  }
}

variable "automq_version" {
  description = "Exact AutoMQ data-plane version already available in the Console"
  type        = string
  default     = "5.5.3"
  nullable    = false

  validation {
    condition     = length(trimspace(var.automq_version)) > 0
    error_message = "automq_version must be an exact version available in the Console."
  }
}

variable "broker_instance_type" {
  description = "EC2 instance type used by all UsageBased AutoMQ broker nodes"
  type        = string
  default     = "m7g.xlarge"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]+$", var.broker_instance_type))
    error_message = "broker_instance_type must be a valid EC2 instance type name."
  }
}

variable "broker_networks" {
  description = "Private broker network placement from the automq-console broker_networks output"
  type = list(object({
    zone    = string
    subnets = list(string)
  }))
  nullable = false

  validation {
    condition = (
      contains([1, 3], length(var.broker_networks)) &&
      length(distinct([for network in var.broker_networks : network.zone])) == length(var.broker_networks) &&
      length(distinct(flatten([for network in var.broker_networks : network.subnets]))) == length(var.broker_networks) &&
      alltrue([
        for network in var.broker_networks :
        trimspace(network.zone) != "" &&
        length(network.subnets) == 1 &&
        try(can(regex("^subnet-([0-9a-f]{8}|[0-9a-f]{17})$", network.subnets[0])), false)
      ])
    )
    error_message = "broker_networks must contain one or three unique zones and exactly one unique valid AWS subnet ID per zone."
  }
}

variable "availability_zone_count" {
  description = "Number of Availability Zones used by the AutoMQ brokers; choose one or three"
  type        = number
  default     = 3
  nullable    = false

  validation {
    condition     = contains([1, 3], var.availability_zone_count)
    error_message = "availability_zone_count must be 1 or 3."
  }
}

variable "data_bucket_name" {
  description = "Terraform-owned S3 data bucket from the automq-console output; required by this EC2 minimal-permissions quick-start"
  type        = string
  nullable    = false

  validation {
    condition = (
      length(var.data_bucket_name) >= 3 &&
      length(var.data_bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.data_bucket_name)) &&
      !strcontains(var.data_bucket_name, "..")
    )
    error_message = "data_bucket_name must be the valid S3 bucket name from the automq-console output."
  }
}

variable "dns_zone_id" {
  description = "Terraform-owned private Route 53 hosted zone ID from the automq-console output; required by this EC2 minimal-permissions quick-start"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.dns_zone_id))
    error_message = "dns_zone_id must be a valid Route 53 hosted zone ID beginning with Z."
  }
}

variable "instance_role_name" {
  description = "Terraform-owned AutoMQ data-plane IAM Role name from the automq-console output; required by this EC2 minimal-permissions quick-start"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.instance_role_name))
    error_message = "instance_role_name must be a valid AWS IAM Role name, not an ARN."
  }
}

variable "wal_mode" {
  description = "Write-ahead log mode for the quick-start instance"
  type        = string
  default     = "S3WAL"
  nullable    = false

  validation {
    condition     = contains(["EBSWAL", "S3WAL", "FSWAL"], upper(var.wal_mode))
    error_message = "wal_mode must be EBSWAL, S3WAL, or FSWAL in this quick-start. FSWAL uses Amazon EFS; FSx WAL is not supported."
  }
}

variable "efs_wal_throughput_mibps_per_file_system" {
  description = "Provisioned Amazon EFS throughput in MiB/s when wal_mode is FSWAL"
  type        = number
  default     = 10
  nullable    = false

  validation {
    condition = (
      floor(var.efs_wal_throughput_mibps_per_file_system) == var.efs_wal_throughput_mibps_per_file_system &&
      var.efs_wal_throughput_mibps_per_file_system >= 10 &&
      var.efs_wal_throughput_mibps_per_file_system <= 1024
    )
    error_message = "efs_wal_throughput_mibps_per_file_system must be an integer between 10 and 1024."
  }
}

variable "instance_configs" {
  description = "Additional AutoMQ broker configuration"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "authentication_methods" {
  description = "Kafka authentication methods supported by this quick-start; use the full provider configuration for mTLS"
  type        = list(string)
  default     = ["anonymous"]
  nullable    = false

  validation {
    condition = (
      length(var.authentication_methods) > 0 &&
      length(distinct(var.authentication_methods)) == length(var.authentication_methods) &&
      alltrue([for method in var.authentication_methods : contains(["anonymous", "sasl"], method)])
    )
    error_message = "authentication_methods must contain unique values from anonymous or sasl."
  }
}

variable "transit_encryption_modes" {
  description = "Kafka transit encryption mode; this quick-start supports plaintext inside the private VPC"
  type        = list(string)
  default     = ["plaintext"]
  nullable    = false

  validation {
    condition = (
      length(var.transit_encryption_modes) == 1 &&
      var.transit_encryption_modes[0] == "plaintext"
    )
    error_message = "This quick-start supports transit_encryption_modes = [\"plaintext\"] only; use the full provider configuration to supply TLS certificates."
  }
}

variable "data_encryption_mode" {
  description = "Data-at-rest encryption mode"
  type        = string
  default     = "NONE"
  nullable    = false

  validation {
    condition     = contains(["NONE", "CPMK"], var.data_encryption_mode)
    error_message = "data_encryption_mode must be NONE or CPMK."
  }
}

variable "schema_registry_enabled" {
  description = "Enable the AutoMQ Schema Registry"
  type        = bool
  default     = false
  nullable    = false
}

variable "tags" {
  description = "Tags applied to the AutoMQ Instance"
  type        = map(string)
  default     = {}
  nullable    = false
}
