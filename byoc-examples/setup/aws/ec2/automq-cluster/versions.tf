terraform {
  required_version = ">= 1.5.7, < 2.0.0"

  required_providers {
    automq = {
      source  = "automq/automq"
      version = "= 0.4.6"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
  }
}

provider "automq" {
  automq_byoc_endpoint      = local.console_endpoint_valid ? local.console_endpoint : "http://127.0.0.1"
  automq_byoc_access_key_id = local.console_access_key_valid ? local.console_access_key : "missing-console-state"
  automq_byoc_secret_key    = local.console_secret_key_valid ? local.console_secret_key : "missing-console-state"
}
