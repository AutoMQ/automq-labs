# Data source for existing EKS cluster information
data "aws_eks_cluster" "eks_cluster" {
  name = var.eks_cluster_name
}

# EKS Add-ons Module
# Installs and configures essential Kubernetes add-ons
module "eks_addons" {
  source = "../../../../kubernetes/aws/terraform/eks-addons"

  region                 = var.region
  cluster_name           = data.aws_eks_cluster.eks_cluster.name

  vpc_id                 = var.vpc_id
  resource_suffix        = var.resource_suffix

  # Default addon configurations - can be overridden via variables
  enable_autoscaler             = var.enable_autoscaler
  enable_alb_ingress_controller = var.enable_alb_ingress_controller
  enable_vpc_cni                = var.enable_vpc_cni
  enable_ebs_csi_driver         = var.enable_ebs_csi_driver

  providers = {
    aws        = aws
    kubernetes = kubernetes
    helm       = helm
  }

  depends_on = [
    data.aws_eks_cluster.eks_cluster
  ]
}

# Security Group Rule: Allow AutoMQ Console access to EKS cluster
resource "aws_vpc_security_group_ingress_rule" "automq_console_ingress_rule" {
  description                  = "Allow inbound traffic from security group of AutoMQ Console"
  from_port                    = 0
  to_port                      = 65535
  ip_protocol                  = "tcp"
  security_group_id            = data.aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  referenced_security_group_id = module.automq-byoc.automq_byoc_security_group_id

  depends_on = [module.automq-byoc]
}

# EKS Access Entry: Grant AutoMQ Console access to the cluster
resource "aws_eks_access_entry" "cluster_admins" {
  cluster_name      = data.aws_eks_cluster.eks_cluster.name
  principal_arn     = module.automq-byoc.automq_byoc_console_role_arn
  kubernetes_groups = []
  type              = "STANDARD"

  depends_on = [module.automq-byoc]
}

# EKS Access Policy: Associate cluster admin policy with AutoMQ Console role
resource "aws_eks_access_policy_association" "cluster_admins" {
  cluster_name  = data.aws_eks_cluster.eks_cluster.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = module.automq-byoc.automq_byoc_console_role_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [module.automq-byoc]
}
