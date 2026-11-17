terraform {
  required_version = ">= 1.9.0"
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "= 2.38.0" }
    helm       = { source = "hashicorp/helm", version = "= 2.17.0" }
  }
}
