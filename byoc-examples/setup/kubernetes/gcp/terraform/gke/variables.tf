variable "project_id" {
  description = "GCP project where the GKE cluster is created."
  type        = string
}

variable "region" {
  description = "GCP region for the regional GKE cluster."
  type        = string
}

variable "zones" {
  description = "Zones used by the default and AutoMQ node pools."
  type        = list(string)
}

variable "name_prefix" {
  description = "Prefix used to derive GKE resource names."
  type        = string
}

variable "network_id" {
  description = "Canonical VPC resource ID."
  type        = string
}

variable "workload_subnet_id" {
  description = "Canonical subnet resource ID used by GKE nodes."
  type        = string
}

variable "pod_secondary_range_name" {
  description = "Secondary subnet range used for GKE Pods."
  type        = string
}

variable "service_secondary_range_name" {
  description = "Secondary subnet range used for GKE Services."
  type        = string
}

variable "automq_node_pool" {
  description = "Capacity settings for the dedicated AutoMQ workload node pool."
  type = object({
    machine_type = string
    min_size     = number
    max_size     = number
  })
}
