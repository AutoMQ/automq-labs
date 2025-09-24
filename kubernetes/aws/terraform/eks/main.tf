# Data source for current AWS account 
data "aws_caller_identity" "current" {}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.2.0"

  name               = local.cluster_name
  kubernetes_version = "1.32"

  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  enable_irsa = true

  eks_managed_node_groups = {
    system_nodes = {
      instance_types = ["t3.medium", "c5.large", "t3.small"]
      desired_size   = 4
      max_size       = 6
      min_size       = 3
      capacity_type  = "SPOT"

      labels = {
        # Node group identification
        "node.kubernetes.io/node-group"    = "system-nodes"
        "node.kubernetes.io/capacity-type" = "spot"

        # Infrastructure labels
        "infrastructure.eks.amazonaws.com/managed-by" = "terraform"
      }
    }
  }

  addons = {
    coredns                = { most_recent = true }
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = { before_compute = true }
    vpc-cni                = { before_compute = true }
  }
}

resource "null_resource" "kube_config" {
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region ${var.region} --name ${local.cluster_name} --no-verify-ssl"
  }
  depends_on = [
    module.eks
  ]
}

# Call eks-addons module to install cluster addons
module "eks_addons" {
  source = "../eks-addons"

  region       = var.region
  cluster_name = module.eks.cluster_name

  vpc_id          = var.vpc_id
  resource_suffix = var.resource_suffix

  # Default addon configurations - can be overridden via variables
  enable_autoscaler             = true
  enable_alb_ingress_controller = true
  enable_ebs_csi_driver         = true

  providers = {
    aws        = aws
    kubernetes = kubernetes
    helm       = helm
  }

  depends_on = [
    module.eks
  ]
}
