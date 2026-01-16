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
}

# EKS Managed Node Group - System Nodes
resource "aws_eks_node_group" "system_nodes" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "system-nodes"
  node_role_arn   = aws_iam_role.node_group_role.arn

  subnet_ids = var.subnet_ids

  capacity_type  = "SPOT"
  instance_types = ["t3.medium", "c5.large", "t3.small"]

  scaling_config {
    desired_size = 4
    max_size     = 6
    min_size     = 3
  }

  labels = {
    # Node group identification
    "node.kubernetes.io/node-group"    = "system-nodes"
    "node.kubernetes.io/capacity-type" = "spot"

    # Infrastructure labels
    "infrastructure.eks.amazonaws.com/managed-by" = "terraform"
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly,
  ]
}

# IAM Role for EKS Node Group
resource "aws_iam_role" "node_group_role" {
  name = "${local.resource_suffix}-node-group-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

# Attach required policies to the node group role
resource "aws_iam_role_policy_attachment" "node_group_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group_role.name
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
  enable_vpc_cni                = true
  enable_coredns                = true
  enable_kube_proxy             = true
  enable_pod_identity_agent     = true
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
