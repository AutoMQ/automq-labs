terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = module.eks-env.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks-env.eks_cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks-env.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks-env.eks_cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
