module "eks-env" {
  source = "../../../setup/kubernetes/aws/terraform"

  region          = var.region
  resource_suffix = local.resource_suffix

  node_group = var.node_group
}

resource "aws_vpc_security_group_ingress_rule" "automq_console_ingress_rule" {
  description                  = "Allow inbound traffic from security group of AutoMQ Console"
  from_port                    = 0
  to_port                      = 65535
  ip_protocol                  = "tcp"
  security_group_id            = module.eks-env.eks_cluster_security_group
  referenced_security_group_id = module.automq-byoc.automq_byoc_security_group_id

  depends_on = [module.automq-byoc, module.eks-env]
}

resource "aws_eks_access_entry" "cluster_admins" {
  cluster_name      = module.eks-env.cluster_name
  principal_arn     = module.automq-byoc.automq_byoc_console_role_arn
  kubernetes_groups = []
  type              = "STANDARD"
  depends_on        = [module.automq-byoc, module.eks-env]
}

resource "aws_eks_access_policy_association" "cluster_admins" {
  cluster_name  = module.eks-env.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = module.automq-byoc.automq_byoc_console_role_arn
  access_scope {
    type = "cluster"
  }
  depends_on = [module.automq-byoc, module.eks-env]
}
