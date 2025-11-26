terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.36.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }

  required_version = "~> 1.3"
}

# Data sources for cluster authentication
data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}
