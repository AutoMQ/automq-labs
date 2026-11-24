variable "console_state_path" {
  description = "Path to the local automq-console state, relative to this directory or absolute"
  type        = string
  default     = "../automq-console/terraform.tfstate"
  nullable    = false

  validation {
    condition     = length(trimspace(var.console_state_path)) > 0
    error_message = "console_state_path must not be empty."
  }
}

variable "kafka_state_path" {
  description = "Path to the local automq-cluster state for the existing Kafka instance"
  type        = string
  default     = "../automq-cluster/terraform.tfstate"
  nullable    = false

  validation {
    condition     = length(trimspace(var.kafka_state_path)) > 0
    error_message = "kafka_state_path must not be empty."
  }
}

variable "console_endpoint_override" {
  description = "Optional Console API URL override, for example http://127.0.0.1:18080 while an SSM tunnel is open"
  type        = string
  default     = null

  validation {
    condition     = var.console_endpoint_override == null ? true : can(regex("^https?://[^[:space:]]+$", var.console_endpoint_override))
    error_message = "console_endpoint_override must be null or an HTTP(S) URL."
  }
}

variable "kubernetes_cluster_id" {
  description = "Existing EKS cluster name in the Console's AWS account and Region; use the name, not its ARN"
  type        = string
  nullable    = false

  validation {
    condition     = length(var.kubernetes_cluster_id) <= 100 && !startswith(var.kubernetes_cluster_id, "REPLACE_") && can(regex("^[A-Za-z0-9][A-Za-z0-9_-]*$", var.kubernetes_cluster_id))
    error_message = "kubernetes_cluster_id must be an EKS cluster name of 1-100 characters, not an ARN or a placeholder."
  }
}

variable "console_eks_access_wait_duration" {
  description = "Buffer for Console IAM and EKS access propagation before creating the Connect Cluster; 0s disables the wait"
  type        = string
  default     = "60s"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+(s|m)$", var.console_eks_access_wait_duration))
    error_message = "console_eks_access_wait_duration must use seconds or minutes, such as 60s or 2m; use 0s to disable the wait."
  }
}

variable "connect_namespace" {
  description = "Dedicated Kubernetes namespace created and owned by this example"
  type        = string
  default     = "automq-connect"
  nullable    = false

  validation {
    condition     = length(var.connect_namespace) <= 63 && !contains(["default", "kube-system", "kube-public", "kube-node-lease"], var.connect_namespace) && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.connect_namespace))
    error_message = "connect_namespace must be a dedicated, non-system namespace with a valid DNS label name."
  }
}

variable "connect_service_account" {
  description = "Dedicated Kubernetes ServiceAccount created in connect_namespace and bound to the new Worker IAM Role"
  type        = string
  default     = "automq-connect"
  nullable    = false

  validation {
    condition     = length(var.connect_service_account) <= 63 && var.connect_service_account != "default" && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.connect_service_account))
    error_message = "connect_service_account must use a dedicated DNS label name of at most 63 characters, other than default."
  }
}

variable "kubernetes_scheduling_spec" {
  description = "Optional Kubernetes scheduling YAML for existing node labels, taints, or affinity rules"
  type        = string
  default     = null

  validation {
    condition     = var.kubernetes_scheduling_spec == null ? true : can(yamldecode(var.kubernetes_scheduling_spec))
    error_message = "kubernetes_scheduling_spec must be null or valid YAML."
  }
}

variable "connect_worker_role_name" {
  description = "Optional name of the new Worker IAM Role; null generates a unique name from the Connect Cluster name"
  type        = string
  default     = null

  validation {
    condition     = var.connect_worker_role_name == null ? true : can(regex("^[A-Za-z0-9_+=,.@-]{1,64}$", var.connect_worker_role_name))
    error_message = "connect_worker_role_name must be null or a valid IAM role name of 1-64 characters."
  }
}

variable "connect_worker_policy_arns" {
  description = "Additional existing IAM managed policy ARNs to attach to the Worker Role beyond the built-in Ops plugin download policy"
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for arn in var.connect_worker_policy_arns : can(regex("^arn:(aws|aws-cn|aws-us-gov):iam::(aws|[0-9]{12}):policy/[A-Za-z0-9_+=,.@/-]+$", arn))
    ])
    error_message = "connect_worker_policy_arns must contain IAM managed policy ARNs, not role or instance profile ARNs."
  }
}

variable "connect_plugin_s3_prefix" {
  description = "Plugin artifact prefix in the Console's Ops Bucket; match the CMP storage path if customized"
  type        = string
  default     = "automq/connect-plugins"
  nullable    = false

  validation {
    condition = (
      length(var.connect_plugin_s3_prefix) > 0 &&
      var.connect_plugin_s3_prefix == trim(var.connect_plugin_s3_prefix, "/") &&
      can(regex("^[A-Za-z0-9._/-]+$", var.connect_plugin_s3_prefix))
    )
    error_message = "connect_plugin_s3_prefix must be a non-empty S3 prefix without wildcards or leading/trailing slashes."
  }
}

variable "connect_cluster_name" {
  description = "Name for the new AutoMQ Connect Cluster"
  type        = string
  default     = "aws-mysql-connect-demo"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{3,64}$", var.connect_cluster_name))
    error_message = "connect_cluster_name must contain 3-64 letters, numbers, underscores, or hyphens."
  }
}

variable "worker_count" {
  description = "Fixed number of Connect workers on the existing EKS cluster"
  type        = number
  default     = 1
  nullable    = false

  validation {
    condition     = var.worker_count >= 1 && floor(var.worker_count) == var.worker_count
    error_message = "worker_count must be a positive integer."
  }
}

variable "worker_resource_spec" {
  description = "AutoMQ Connect worker resource tier"
  type        = string
  default     = "TIER1"
  nullable    = false

  validation {
    condition     = contains(["TIER1", "TIER2", "TIER3", "TIER4"], var.worker_resource_spec)
    error_message = "worker_resource_spec must be TIER1, TIER2, TIER3, or TIER4."
  }
}

variable "connect_version" {
  description = "Optional Connect worker version available in the Console; null selects the backend default"
  type        = string
  default     = null

  validation {
    condition     = var.connect_version == null ? true : length(trimspace(var.connect_version)) > 0
    error_message = "connect_version must be null or an available Connect worker version."
  }
}

variable "plugin_name" {
  description = "Existing MySQL Debezium plugin name in the Console plugin catalog"
  type        = string
  default     = "mysql-debezium-cdc"
  nullable    = false

  validation {
    condition     = length(trimspace(var.plugin_name)) > 0
    error_message = "plugin_name must not be empty."
  }
}

variable "plugin_version" {
  description = "Exact ACTIVE version of plugin_name from your Console plugin catalog"
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.plugin_version)) > 0 && !startswith(var.plugin_version, "REPLACE_")
    error_message = "plugin_version must be an actual ACTIVE version from the Console plugin catalog."
  }
}

variable "tags" {
  description = "Tags for the AutoMQ Connect Cluster"
  type        = map(string)
  default     = { purpose = "evaluation" }
  nullable    = false
}
variable "aws_region" {
  description = "AWS Region of the external EKS cluster; must match the Console and Kafka instance Region"
  type        = string
  default     = "us-east-1"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be an AWS Region name such as us-east-1."
  }
}

variable "aws_profile" {
  description = "Optional shared AWS profile used by both the AWS provider and Kubernetes exec authentication; null uses the default credential chain"
  type        = string
  default     = null

  validation {
    condition     = var.aws_profile == null ? true : length(trimspace(var.aws_profile)) > 0
    error_message = "aws_profile must be null or a non-empty shared profile name."
  }
}
