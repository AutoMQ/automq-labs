variable "name_prefix" {
  description = "Unique resource name prefix for the AutoMQ data-plane role"
  type        = string
}

variable "data_bucket_name" {
  description = "S3 bucket used by AutoMQ data-plane storage"
  type        = string
}

variable "ops_bucket_name" {
  description = "S3 bucket used by AutoMQ operational artifacts"
  type        = string
}

variable "hosted_zone_id" {
  description = "Private Route 53 hosted zone used by AutoMQ brokers"
  type        = string
}

variable "tags" {
  description = "Tags applied to IAM resources"
  type        = map(string)
  default     = {}
}
