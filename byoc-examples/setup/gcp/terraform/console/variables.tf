variable "project_id" {
  description = "GCP project where the Console resources are created."
  type        = string
}

variable "region" {
  description = "GCP region for regional Console resources."
  type        = string
}

variable "zone" {
  description = "GCP zone for the Console VM and data disk."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used for Console resource names."
  type        = string
}

variable "network_id" {
  description = "Canonical ID of the VPC used by the Console firewall."
  type        = string
}

variable "management_subnet_id" {
  description = "Canonical ID of the management subnet used by the Console."
  type        = string
}

variable "config" {
  description = "Base64-encoded AutoMQ BYOC CONFIG value."
  type        = string
  sensitive   = true
}

variable "console_image" {
  description = "AutoMQ GCP Console container image."
  type        = string
}

variable "home_endpoint" {
  description = "AutoMQ Cloud endpoint used by the Console."
  type        = string
}

variable "machine_type" {
  description = "GCE machine type used by the Console VM."
  type        = string
}

variable "ingress_source_ranges" {
  description = "IPv4 CIDR ranges allowed to access the Console."
  type        = list(string)
}

variable "registry" {
  description = "Optional private container registry credentials."
  type = object({
    server   = string
    username = string
    password = string
  })
  sensitive = true
}
