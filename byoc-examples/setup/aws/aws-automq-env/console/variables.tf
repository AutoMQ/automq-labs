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
  description = "Explicit repository:8.x.y-aws tag for the released AWS Console image supplied with your AutoMQ installation command. Chart AppVersion does not select this image."
  type        = string
  validation {
    condition     = can(regex("^.+:8\\.[0-9]+\\.[0-9]+-aws$", var.console_image)) && !strcontains(var.console_image, "<")
    error_message = "Specify an explicit released AWS Console repository:8.x.y-aws tag; latest, snapshots and placeholders are rejected."
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
