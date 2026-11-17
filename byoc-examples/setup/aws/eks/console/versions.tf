terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "= 6.28.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "= 2.38.0" }
    helm       = { source = "hashicorp/helm", version = "= 2.17.0" }
  }
}
