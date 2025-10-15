# Node group outputs
output "node_group_name" {
  description = "Name of the created node group"
  value       = aws_eks_node_group.benchmark_nodes.node_group_name
}

output "node_group_arn" {
  description = "ARN of the created node group"
  value       = aws_eks_node_group.benchmark_nodes.arn
}

output "node_group_status" {
  description = "Status of the node group"
  value       = aws_eks_node_group.benchmark_nodes.status
}

output "node_group_capacity_type" {
  description = "Capacity type of the node group"
  value       = aws_eks_node_group.benchmark_nodes.capacity_type
}

output "node_group_instance_types" {
  description = "Instance types used by the node group"
  value       = aws_eks_node_group.benchmark_nodes.instance_types
}

output "node_group_scaling_config" {
  description = "Scaling configuration of the node group"
  value = {
    desired_size = aws_eks_node_group.benchmark_nodes.scaling_config[0].desired_size
    max_size     = aws_eks_node_group.benchmark_nodes.scaling_config[0].max_size
    min_size     = aws_eks_node_group.benchmark_nodes.scaling_config[0].min_size
  }
}

output "node_group_labels" {
  description = "Labels applied to the node group"
  value       = aws_eks_node_group.benchmark_nodes.labels
}

# Cluster information
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = data.aws_eks_cluster.existing.name
}

output "cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  value       = data.aws_eks_cluster.existing.endpoint
}

output "cluster_version" {
  description = "Version of the EKS cluster"
  value       = data.aws_eks_cluster.existing.version
}

# Node selector and tolerations for workload scheduling
output "node_selector_labels" {
  description = "Labels to use for node selection in pod specs"
  value = {
    "node.kubernetes.io/node-group" = aws_eks_node_group.benchmark_nodes.node_group_name
    "workload-type"                 = "benchmark"
    "environment"                   = var.environment
  }
}

output "tolerations" {
  description = "Tolerations to use in pod specs if dedicated nodes are enabled"
  value = var.enable_dedicated_nodes ? [
    {
      key      = "workload-type"
      operator = "Equal"
      value    = "benchmark"
      effect   = "NoSchedule"
    }
  ] : []
}