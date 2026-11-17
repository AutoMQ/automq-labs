variable "region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the cluster is deployed"
  type        = string
}

variable "resource_suffix" {
  description = "Suffix for resource names"
  type        = string
}

variable "enable_autoscaler" {
  description = "Enable the Kubernetes Cluster Autoscaler"
  type        = bool
  default     = true
}

variable "enable_alb_ingress_controller" {
  description = "Enable the AWS Load Balancer Controller"
  type        = bool
  default     = true
}

variable "enable_ebs_csi_driver" {
  description = "Enable the AWS EBS CSI addon"
  type        = bool
  default     = true
}

variable "enable_vpc_cni" {
  description = "Enable the AWS VPC CNI addon"
  type        = bool
  default     = false
}

variable "enable_coredns" {
  description = "Enable the CoreDNS addon"
  type        = bool
  default     = false
}

variable "enable_kube_proxy" {
  description = "Enable the kube-proxy addon"
  type        = bool
  default     = false
}

variable "enable_pod_identity_agent" {
  description = "Enable the EKS Pod Identity Agent addon"
  type        = bool
  default     = false
}

variable "role_arns" {
  description = "Existing component IRSA role ARNs keyed by autoscaler, lb-controller or ebs-csi. Missing keys retain the existing module-owned IRSA roles."
  type        = map(string)
  default     = {}
}

variable "enable_external_dns" {
  description = "Install the existing ExternalDNS release and role. Disable when Console manages private DNS."
  type        = bool
  default     = true
}

variable "enable_automq_ingress_rule" {
  description = "Preserve the existing AutoMQ port ingress rule; disable when the caller manages workload network access."
  type        = bool
  default     = true
}

variable "manage_lb_service_account" {
  description = "Manage the LB controller ServiceAccount separately as before. Set false to let its Helm Chart manage the account with role_arns."
  type        = bool
  default     = true
}

variable "autoscaler_image_tag" {
  description = "Cluster Autoscaler image tag, which must match the EKS minor version."
  type        = string
  default     = "v1.36.1"
}

variable "autoscaler_chart_version" {
  description = "Cluster Autoscaler Helm Chart version."
  type        = string
  default     = "9.59.0"
}

variable "lb_controller_chart_version" {
  description = "Optional LB controller Chart pin; null preserves the existing unpinned selection."
  type        = string
  default     = null
}

variable "autoscaler_values" {
  description = "Additional YAML values documents merged after the existing Autoscaler values."
  type        = list(string)
  default     = []
}

variable "lb_controller_values" {
  description = "Additional YAML values documents merged after the existing LB controller values."
  type        = list(string)
  default     = []
}

variable "lb_controller_host_network" {
  description = "LB controller hostNetwork setting; existing callers retain true."
  type        = bool
  default     = true
}
