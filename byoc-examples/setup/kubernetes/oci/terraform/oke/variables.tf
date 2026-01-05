# Basic Variables
variable "tenancy_ocid" {
  description = "The OCID of the tenancy"
  type        = string
}

variable "oci_profile" {
  description = "The OCI CLI profile to use"
  type        = string
}

variable "compartment_id" {
  description = "The OCID of the compartment where resources will be created"
  type        = string
}

variable "region" {
  description = "Cloud region to deploy to (e.g. us-ashburn-1)"
  type        = string
}

variable "oke_cluster_name" {
  description = "OKE Cluster Name."
  type        = string
}

# Network Variables
variable "vcn_id" {
  description = "The OCID of the existing VCN to use."
  type        = string
}

variable "control_plane_subnet_id" {
  description = "The OCID of the existing subnet for the OKE control plane."
  type        = string
}

variable "worker_subnet_id" {
  description = "The OCID of the existing subnet for the OKE worker nodes."
  type        = string
}

variable "pod_subnet_id" {
  description = "The OCID of the existing subnet for the OKE pods."
  type        = string
}

variable "lb_subnet_id" {
  description = "The OCID of the existing subnet for load balancers."
  type        = string
}

# Node Configuration
variable "node_config" {
  description = "List of values for the node configuration of kubernetes cluster"
  type = object({
    node_type        = string
    ocpus            = number
    size             = number
    memory           = number
    boot_volume_size = number
  })
  default = {
    node_type        = "VM.Standard.E5.Flex"
    ocpus            = 2
    size             = 3
    memory           = 16
    boot_volume_size = 50
  }
}

# Tags
variable "common_tags" {
  description = "additional tags for merging with common tags"
  type        = map(string)
  default     = {}
}

variable "control_plane_is_public" {
  description = "Whether the OKE control plane should have a public IP."
  type        = bool
  default     = false
}
