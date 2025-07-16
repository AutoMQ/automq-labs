# -----------------------------------------------------------------------------
# Provider Configuration
# -----------------------------------------------------------------------------

# AWS Provider configuration
provider "aws" {
  region = var.region
}

# Data sources for EKS cluster authentication
data "aws_eks_cluster_auth" "cluster" {
  name = var.eks_cluster_name
}

# Kubernetes Provider - connects to existing EKS cluster
provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks_cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks_cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# Helm Provider - for installing Helm charts on the EKS cluster
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks_cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks_cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# Data source for available AWS availability zones
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}