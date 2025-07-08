variable "region" {
  description = "AWS region"
  type        = string
}

variable "resource_suffix" {
  description = "Suffix for resource names"
  type        = string
}

variable "data_bucket_name" {
  description = "Name of the S3 bucket for data storage"
  type        = string
  default = "*"
}

variable "ops_bucket_name" {
  description = "Name of the S3 bucket for data storage"
  type        = string
  default = "*"
}
