# Data source to get the existing node group IAM role
data "aws_iam_role" "benchmark_node_group_role" {
  count = var.enable_benchmark_nodes ? 1 : 0
  name  = var.benchmark_node_role_name
}

# Benchmark Node Group
resource "aws_eks_node_group" "benchmark_node_group" {
  count           = var.enable_benchmark_nodes ? 1 : 0
  cluster_name    = module.eks-env.cluster_name
  node_group_name = "benchmark-node-group-${var.resource_suffix}"
  node_role_arn   = data.aws_iam_role.benchmark_node_group_role[0].arn
  
  # Use the same subnet as the default node group (single AZ for cost optimization)
  subnet_ids = slice(module.eks-env.private_subnets, 0, 1)

  scaling_config {
    desired_size = var.benchmark_desired_size
    max_size     = var.benchmark_max_size
    min_size     = var.benchmark_min_size
  }

  capacity_type   = var.benchmark_capacity_type
  instance_types  = var.benchmark_instance_types
  ami_type        = var.benchmark_ami_type
  disk_size       = var.benchmark_disk_size

  labels = merge(
    {
      "node-type"     = "benchmark"
      "workload-type" = "benchmark"
    }
  )

  # Add taints for dedicated benchmark nodes if enabled
  dynamic "taint" {
    for_each = var.benchmark_enable_dedicated_nodes ? [1] : []
    content {
      key    = "benchmark-node"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }

  tags = merge(
    {
      Name        = "benchmark-node-group-${var.resource_suffix}"
    }
  )

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  depends_on = [
    module.eks-env
  ]
}