variable "infrastructure_state_path" {
  type    = string
  default = "../infrastructure/terraform.tfstate"
}
variable "automq_config" {
  description = "Complete base64 CONFIG, supplied through TF_VAR_automq_config. Runtime state contains this secret."
  type        = string
  sensitive   = true
  validation {
    condition     = try(alltrue([for key in ["environmentId", "region", "clientId", "clientSecret"] : length(trimspace(jsondecode(base64decode(var.automq_config))[key])) > 0]) && length(trimspace(jsondecode(base64decode(var.automq_config)).opsBucket.bucketName)) > 0, false)
    error_message = "automq_config must be a complete base64-encoded JSON CONFIG."
  }
}
variable "console_image" {
  description = "Explicit repository:tag containing the ServiceAccount, strict managed IRSA trust and S3WAL fixes. Chart AppVersion is not a compatible image default."
  type        = string
  validation {
    condition     = can(regex("^.+:[^/:@]+$", var.console_image)) && !can(regex(":(latest|8\\.3\\.28(-aws)?)$", var.console_image)) && !strcontains(var.console_image, "<")
    error_message = "Specify a compatible repository:tag; latest and the incompatible 8.3.28 image are rejected."
  }
}
variable "console_chart_path" {
  description = "Optional local copy of the pinned official Chart for offline validation."
  type        = string
  default     = null
  nullable    = true
}
variable "deployer_assume_role_arn" {
  description = "Optional explicit cross-role token path. Default uses the current AWS profile session without self-assume. Never use the Console role."
  type        = string
  default     = null
  nullable    = true
}
