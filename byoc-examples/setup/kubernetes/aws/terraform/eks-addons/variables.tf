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
