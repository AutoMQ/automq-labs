terraform {
  required_version = ">= 1.5.7, < 2.0.0"

  required_providers {
    automq = {
      source  = "automq/automq"
      version = "= 0.4.5"
    }
  }
}

provider "automq" {
  automq_byoc_endpoint      = var.console_endpoint
  automq_byoc_access_key_id = var.console_access_key
  automq_byoc_secret_key    = var.console_secret_key
}
