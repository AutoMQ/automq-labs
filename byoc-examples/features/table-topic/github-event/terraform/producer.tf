# Producer Node Group
resource "aws_eks_node_group" "producer_node_group" {
  count           = 1
  cluster_name    = module.eks-env.cluster_name
  node_group_name = "producer-node-group-${local.resource_suffix}"
  node_role_arn   = module.eks-env.node_role_arn

  # Use the same subnet as the default node group (single AZ for cost optimization)
  subnet_ids = slice(module.eks-env.private_subnets, 0, 1)

  scaling_config {
    desired_size = var.producer_desired_size
    max_size     = var.producer_max_size
    min_size     = var.producer_min_size
  }

  capacity_type  = var.producer_capacity_type
  instance_types = var.producer_instance_types
  ami_type       = var.producer_ami_type
  disk_size      = var.producer_disk_size

  labels = merge(
    {
      "node-type"     = "producer"
      "workload-type" = "producer"
    }
  )

  tags = merge(
    {
      Name = "producer-node-group-${local.resource_suffix}"
    }
  )

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  depends_on = [
    module.eks-env
  ]
}