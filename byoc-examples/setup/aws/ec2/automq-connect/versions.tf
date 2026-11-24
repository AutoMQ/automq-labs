terraform {
  required_version = ">= 1.7.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    automq = {
      source  = "automq/automq"
      version = "= 0.4.10"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.target.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.target.certificate_authority[0].data)

  # Refresh short-lived EKS tokens during long-running applies and destroys.
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = concat(
      ["eks", "get-token", "--cluster-name", var.kubernetes_cluster_id, "--region", var.aws_region],
      var.aws_profile == null ? [] : ["--profile", var.aws_profile],
    )
  }
}

provider "automq" {
  automq_byoc_endpoint      = local.console_endpoint_valid ? local.console_endpoint : "http://127.0.0.1"
  automq_byoc_access_key_id = local.console_access_key_valid ? local.console_access_key : "missing-console-state"
  automq_byoc_secret_key    = local.console_secret_key_valid ? local.console_secret_key : "missing-console-state"
}
