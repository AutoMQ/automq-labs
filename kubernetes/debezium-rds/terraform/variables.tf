variable "database_type" {
  type        = string
  description = "Must be 'mysql' or 'postgresql'"

  validation {
    condition     = contains(["mysql", "postgresql"], var.database_type)
    error_message = "database_type must be 'mysql' or 'postgresql'"
  }
}
