variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs"
  type        = list(string)
}

variable "resource_depends_on" {
  description = "Resources that this module depends on"
  default     = null
}

variable "resource_suffix" {
  description = "Suffix for resource names"
  type        = string
}

variable "cluster_name" {
  description = "EKS Cluster name (overrides default naming)"
  type        = string
  default     = ""
}

variable "cluster_options" {
  description = "Optional cluster settings; defaults preserve the existing EKS module behavior."
  type = object({
    kubernetes_version                       = optional(string, "1.36")
    service_ipv4_cidr                        = optional(string)
    endpoint_private_access                  = optional(bool, true)
    endpoint_public_access                   = optional(bool, true)
    endpoint_public_access_cidrs             = optional(list(string), ["0.0.0.0/0"])
    authentication_mode                      = optional(string, "API_AND_CONFIG_MAP")
    enable_cluster_creator_admin_permissions = optional(bool, true)
    deployer_role_arn                        = optional(string)
    enabled_log_types                        = optional(list(string), ["audit", "api", "authenticator"])
    log_retention_days                       = optional(number, 90)
  })
  default  = {}
  nullable = false
}

variable "system_node_group" {
  description = "System managed node group. Terraform owns desired_size; workload pools below delegate it to Cluster Autoscaler."
  type = object({
    name               = optional(string, "system-nodes")
    subnet_ids         = optional(list(string))
    instance_types     = optional(list(string), ["t3.medium", "c5.large", "t3.small"])
    capacity_type      = optional(string, "SPOT")
    ami_type           = optional(string)
    kubernetes_version = optional(string)
    min_size           = optional(number, 3)
    desired_size       = optional(number, 4)
    max_size           = optional(number, 6)
    labels = optional(map(string), {
      "node.kubernetes.io/node-group"               = "system-nodes"
      "node.kubernetes.io/capacity-type"            = "spot"
      "infrastructure.eks.amazonaws.com/managed-by" = "terraform"
    })
    launch_template_key = optional(string)
    max_unavailable     = optional(number)
  })
  default  = {}
  nullable = false
  validation {
    condition     = var.system_node_group.min_size <= var.system_node_group.desired_size && var.system_node_group.desired_size <= var.system_node_group.max_size
    error_message = "The system node group must satisfy min_size <= desired_size <= max_size."
  }
}

variable "workload_node_groups" {
  description = "Additional managed node groups keyed by pool/AZ; defaults create no business nodes. Cluster Autoscaler owns desired capacity after creation."
  type = map(object({
    name                = string
    subnet_ids          = list(string)
    instance_types      = list(string)
    capacity_type       = optional(string, "ON_DEMAND")
    ami_type            = optional(string)
    kubernetes_version  = optional(string)
    min_size            = number
    desired_size        = number
    max_size            = number
    labels              = optional(map(string), {})
    taints              = optional(list(object({ key = string, value = string, effect = string })), [])
    launch_template_key = optional(string)
    max_unavailable     = optional(number, 1)
  }))
  default  = {}
  nullable = false
  validation {
    condition     = alltrue([for pool in var.workload_node_groups : pool.min_size <= pool.desired_size && pool.desired_size <= pool.max_size])
    error_message = "Every workload node group must satisfy min_size <= desired_size <= max_size."
  }
}

variable "node_iam" {
  description = "Node IAM settings. Existing callers retain CNI and ECR read-only policies; callers using component IRSA can remove CNI from Nodes."
  type = object({
    role_name         = optional(string)
    attach_cni_policy = optional(bool, true)
    ecr_policy_name   = optional(string, "AmazonEC2ContainerRegistryReadOnly")
  })
  default  = {}
  nullable = false
}

variable "node_launch_templates" {
  description = "Optional node launch templates keyed by names selected in the node groups. No templates are added for existing callers."
  type = map(object({
    name_prefix           = string
    root_volume_size      = optional(number, 40)
    root_volume_encrypted = optional(bool, true)
    metadata_hop_limit    = optional(number, 1)
  }))
  default  = {}
  nullable = false
}

variable "component_irsa_prefix" {
  description = "When set, create separate cni, ebs-csi, autoscaler and lb-controller Pod roles with this exact name prefix."
  type        = string
  default     = null
}

variable "manage_core_addons" {
  description = "Manage CNI before nodes and CoreDNS/kube-proxy/CSI after system nodes in this AWS stage; otherwise the existing embedded addons stage manages them."
  type        = bool
  default     = false
}

variable "addon_versions" {
  description = "Optional exact managed addon versions; otherwise resolve versions compatible with cluster_options.kubernetes_version."
  type        = map(string)
  default     = {}
}

variable "install_addons" {
  description = "Install the existing embedded EKS/Helm addons. Disable for a separate post-cluster eks-addons stage."
  type        = bool
  default     = true
}

variable "manage_kubeconfig" {
  description = "Keep the existing local update-kubeconfig action; disable when the caller uses its own isolated kubeconfig wrapper."
  type        = bool
  default     = true
}

variable "enable_autoscaler_discovery" {
  description = "Tag managed node groups and their underlying ASGs for Cluster Autoscaler discovery."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags for explicitly configured cluster and node resources."
  type        = map(string)
  default     = {}
}
