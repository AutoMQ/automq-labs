# Data sources to reference existing EKS cluster
data "aws_eks_cluster" "existing" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "existing" {
  name = var.cluster_name
}

# Data source to reference existing IAM role
data "aws_iam_role" "existing_node_role" {
  name = var.existing_node_role_name
}

# Create the new node group for load testing
resource "aws_eks_node_group" "benchmark_nodes" {
  cluster_name    = data.aws_eks_cluster.existing.name
  node_group_name = "benchmark-${var.resource_suffix}"
  node_role_arn   = data.aws_iam_role.existing_node_role.arn
  subnet_ids      = var.subnet_ids

  # Scaling configuration - at least 1 node with 4c8g
  scaling_config {
    desired_size = var.desired_size
    max_size     = var.max_size
    min_size     = var.min_size
  }

  # Update configuration
  update_config {
    max_unavailable = 1
  }

  # Instance configuration - 4c8g instances
  capacity_type  = var.capacity_type
  instance_types = var.instance_types
  ami_type       = var.ami_type
  disk_size      = var.disk_size

  # Labels for the node group
  labels = merge(
    {
      "node.kubernetes.io/node-group"                    = "benchmark-${var.resource_suffix}"
      "infrastructure.eks.amazonaws.com/managed-by"      = "terraform"
      "node.kubernetes.io/capacity-type"                 = lower(var.capacity_type)
      "workload-type"                                     = "benchmark"
      "environment"                                       = var.environment
    },
    var.additional_labels
  )

  # Optional taints for dedicated nodes
  dynamic "taint" {
    for_each = var.enable_dedicated_nodes ? [1] : []
    content {
      key    = "workload-type"
      value  = "benchmark"
      effect = "NO_SCHEDULE"
    }
  }

  # Remote access configuration (optional)
  dynamic "remote_access" {
    for_each = var.enable_remote_access ? [1] : []
    content {
      ec2_ssh_key               = var.ec2_ssh_key
      source_security_group_ids = var.source_security_group_ids
    }
  }

  # Tags
  tags = merge(
    {
      Name        = "benchmark-${var.resource_suffix}"
      Environment = var.environment
      ManagedBy   = "terraform"
      Purpose     = "benchmark"
    },
    var.additional_tags
  )

  # Ensure proper ordering
  depends_on = [
    data.aws_eks_cluster.existing,
    data.aws_iam_role.existing_node_role
  ]
}