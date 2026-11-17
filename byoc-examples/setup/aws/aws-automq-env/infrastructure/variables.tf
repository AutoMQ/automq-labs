variable "automq_config" {
  description = "Complete Base64 CONFIG from the AWS BYOC installation command."
  type        = string
  sensitive   = true
  nullable    = false
  validation {
    condition = try(alltrue([for value in [
      jsondecode(base64decode(var.automq_config)).environmentId,
      jsondecode(base64decode(var.automq_config)).clientId,
      jsondecode(base64decode(var.automq_config)).clientSecret,
      jsondecode(base64decode(var.automq_config)).region,
      jsondecode(base64decode(var.automq_config)).opsBucket.bucketName,
    ] : trimspace(value) != ""]), false)
    error_message = "automq_config must contain valid Base64 JSON with environmentId, clientId, clientSecret, region, and opsBucket.bucketName."
  }
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", jsondecode(base64decode(var.automq_config)).opsBucket.bucketName))
    error_message = "CONFIG opsBucket.bucketName must be an AWS S3 bucket name, not an Azure account:container ID."
  }
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", jsondecode(base64decode(var.automq_config)).region))
    error_message = "CONFIG region must be a valid AWS region name."
  }
}

variable "name_prefix" {
  description = "Unique lowercase prefix for the new EKS foundation."
  type        = string
  default     = "automq-eks-demo"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.name_prefix))
    error_message = "name_prefix must be 3-25 lowercase letters, digits, or hyphens and start with a letter."
  }
}

variable "vpc_id" {
  description = "Existing VPC; this configuration never takes ownership of it."
  type        = string
  validation {
    condition     = can(regex("^vpc-[a-f0-9]+$", var.vpc_id))
    error_message = "vpc_id must be a non-empty AWS VPC ID."
  }
}

variable "private_subnet_ids_by_az" {
  description = "Exactly three AZ names mapped to distinct private subnet IDs in vpc_id."
  type        = map(string)
  validation {
    condition     = length(var.private_subnet_ids_by_az) == 3 && length(distinct(values(var.private_subnet_ids_by_az))) == 3 && alltrue([for id in values(var.private_subnet_ids_by_az) : can(regex("^subnet-[a-f0-9]+$", id))])
    error_message = "private_subnet_ids_by_az must map exactly three distinct AZs to distinct valid subnet IDs."
  }
}

variable "s3_vpc_endpoint_id" {
  description = "Existing S3 Gateway Endpoint associated with every selected private subnet route table. Its policy must permit Ops and future managed Data Buckets."
  type        = string
  validation {
    condition     = can(regex("^vpce-[a-f0-9]+$", var.s3_vpc_endpoint_id))
    error_message = "s3_vpc_endpoint_id must be a valid endpoint ID."
  }
}

variable "create_private_nat_egress" {
  description = "Explicitly create one evaluation EIP/NAT and default routes in selected private route tables that have no existing default. Existing routes are never adopted or replaced."
  type        = bool
  default     = false
}

variable "nat_public_subnet_id" {
  description = "Existing same-VPC public subnet for the optional NAT, with an attached Internet Gateway default route. Required only when create_private_nat_egress=true."
  type        = string
  default     = null
  validation {
    condition     = !var.create_private_nat_egress || can(regex("^subnet-[a-f0-9]+$", var.nat_public_subnet_id))
    error_message = "nat_public_subnet_id must be a valid existing public subnet ID when create_private_nat_egress is enabled."
  }
}

variable "deployer_role_arn" {
  description = "IAM role (not STS session ARN) used to install Kubernetes/Helm resources; independent of the Console Role."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.deployer_role_arn))
    error_message = "deployer_role_arn must be an IAM Role ARN, not an assumed-role session or the Console Role."
  }
}

variable "kubernetes_version" {
  description = "Explicit EKS version supported in the target region and compatible with the selected AutoMQ release."
  type        = string
  default     = "1.36"
  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must be an explicit major.minor version."
  }
}

variable "addon_versions" {
  description = "Optional exact versions for vpc-cni, coredns, kube-proxy and aws-ebs-csi-driver. Copy resolved addon_versions output here to reproduce a tested deployment; omitted entries use the current EKS-compatible version."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for name, version in var.addon_versions : contains(["vpc-cni", "coredns", "kube-proxy", "aws-ebs-csi-driver"], name) && can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", version))])
    error_message = "addon_versions keys must name a supported add-on and values must be exact vX.Y.Z-eksbuild.N versions."
  }
}

variable "public_api_allowed_cidrs" {
  description = "Optional public EKS API allowlist. Empty disables public API; run Terraform from a network that can reach the private API."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for cidr in var.public_api_allowed_cidrs : can(cidrnetmask(cidr)) && !contains(["0.0.0.0/0"], cidr)])
    error_message = "public_api_allowed_cidrs must contain valid IPv4 CIDRs and must not include 0.0.0.0/0."
  }
}

variable "service_ipv4_cidr" {
  description = "Kubernetes Service IPv4 CIDR, distinct from every VPC CIDR."
  type        = string
  default     = "172.20.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.service_ipv4_cidr)) && can(regex("/(1[2-9]|2[0-4])$", var.service_ipv4_cidr)) && can(regex("^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.)", var.service_ipv4_cidr)) && try(split("/", var.service_ipv4_cidr)[0] == cidrhost(var.service_ipv4_cidr, 0), false)
    error_message = "service_ipv4_cidr must be a canonical private IPv4 /12 through /24 CIDR."
  }
}

variable "console_namespace" {
  description = "Dedicated namespace for the Console, separate from managed Instance namespaces."
  type        = string
  default     = "automq-console"
  validation {
    condition     = length(var.console_namespace) <= 63 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.console_namespace))
    error_message = "console_namespace must be a valid Kubernetes DNS label."
  }
}

variable "console_service_account_name" {
  description = "Pre-created Console ServiceAccount referenced by the Console Chart."
  type        = string
  default     = "automq-console"
  validation {
    condition     = length(var.console_service_account_name) <= 63 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.console_service_account_name))
    error_message = "console_service_account_name must be a valid Kubernetes DNS label."
  }
}

variable "system_instance_type" {
  description = "x86_64 system node size; must provide capacity for Console requests plus system components."
  type        = string
  default     = "m7i.large"
}

variable "automq_instance_type" {
  description = "ARM64 EC2 size for all three AutoMQ pools; select a compatible AutoMQ Instance specification."
  type        = string
  default     = "m7g.xlarge"
  validation {
    condition     = can(regex("^[a-z][a-z0-9]*g[a-z0-9]*\\.[a-z0-9]+$", var.automq_instance_type))
    error_message = "automq_instance_type must be an ARM Graviton instance type compatible with AL2023_ARM_64_STANDARD."
  }
}

variable "automq_max_nodes_per_az" {
  description = "Maximum AutoMQ nodes in each AZ; each group initially has one node."
  type        = number
  default     = 4
  validation {
    condition     = var.automq_max_nodes_per_az >= 1 && floor(var.automq_max_nodes_per_az) == var.automq_max_nodes_per_az
    error_message = "automq_max_nodes_per_az must be a positive integer."
  }
}

variable "system_max_nodes" {
  description = "Maximum system nodes; the initial two nodes are On-Demand."
  type        = number
  default     = 4
  validation {
    condition     = var.system_max_nodes >= 2 && floor(var.system_max_nodes) == var.system_max_nodes
    error_message = "system_max_nodes must be an integer of at least two."
  }
}
