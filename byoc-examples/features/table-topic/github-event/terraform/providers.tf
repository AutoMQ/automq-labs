terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = " > 5.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
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

# Configure AWS Provider
provider "aws" {
  region = var.region
}

# Configure Kubernetes provider to connect to the EKS cluster
provider "kubernetes" {
  host                   = module.eks-env.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks-env.eks_cluster_ca_certificate)

  # Use AWS CLI to obtain EKS token dynamically
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks-env.cluster_name,
    ]
  }
}

# Configure Helm provider using the same Kubernetes connection
provider "helm" {
  kubernetes {
    host                   = module.eks-env.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks-env.eks_cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.eks-env.cluster_name,
      ]
    }
  }
}