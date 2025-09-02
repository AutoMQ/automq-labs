# Data source for current AWS account 
data "aws_caller_identity" "current" {}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0.0"

  name               = local.cluster_name
  kubernetes_version = "1.32"

  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids
}

resource "aws_eks_node_group" "system-nodes" {
  cluster_name    = local.cluster_name
  node_group_name = local.system_node_group_name
  node_role_arn   = aws_iam_role.nodes.arn

  subnet_ids = [local.private_subnet_ids[0]]

  ami_type       = "AL2_x86_64"
  capacity_type  = "SPOT"
  instance_types = ["t3.medium", "c5.large", "t3.small"]

  scaling_config {
    desired_size = 4
    max_size     = 5
    min_size     = 3
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    node_type                      = "spot"
    "node.kubernetes.io/lifecycle" = "normal"
  }

  depends_on = [
    module.eks,
    var.resource_depends_on,
    aws_iam_role_policy_attachment.nodes-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.nodes-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.nodes-AmazonEC2ContainerRegistryReadOnly,
  ]
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
  enable_vpc_cni                = true
  enable_ebs_csi_driver         = true

  providers = {
    aws        = aws
    kubernetes = kubernetes
    helm       = helm
  }

  depends_on = [
    module.eks, aws_eks_node_group.system-nodes
  ]
}
