# IAM module: Configures required IAM roles and permissions for the cluster
module "cluster-iam" {
  source           = "../../../../kubernetes/aws/terraform/iam"
  region           = local.region
  resource_suffix  = local.resource_suffix
  ops_bucket_name  = "*"
  data_bucket_name = "*"
}

# EKS Node Group: Configure worker nodes for AutoMQ workloads
resource "aws_eks_node_group" "automq-node-groups" {
  cluster_name    = var.eks_cluster_name
  node_group_name = local.node_group.name
  node_role_arn   = module.cluster-iam.node_group_role_arn

  # Optional: Use multi-AZ configuration
  # subnet_ids = var.private_subnet_ids

  # Current config: Use single AZ to reduce costs
  subnet_ids = slice(var.private_subnet_ids, 0, 1)

  ami_type       = local.node_group.ami_type
  capacity_type  = "ON_DEMAND"
  instance_types = [local.node_group.instance_type]

  # Node group auto-scaling configuration
  scaling_config {
    desired_size = local.node_group.desired_size
    max_size     = local.node_group.max_size
    min_size     = local.node_group.min_size
  }

  # Node taints: Ensures only specific pods are scheduled to these nodes
  taint {
    key    = "dedicated"
    value  = "automq"
    effect = "NO_SCHEDULE"
  }

  labels = {}

  tags = {}

  depends_on = [
    data.aws_eks_cluster.eks_cluster,
    module.cluster-iam
  ]
}