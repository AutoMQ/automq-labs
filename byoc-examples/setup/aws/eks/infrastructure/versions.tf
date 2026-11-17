terraform {
  required_version = ">= 1.9.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.28.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "= 4.1.0"
    }
  }
}

provider "aws" {
  region = local.region
}
