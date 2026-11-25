locals {
  # IAM policy APIs take the role name, without its optional IAM path.
  console_role_name = try(regex("/([^/]+)$", local.console_role_arn)[0], "missing-console-state")
  eks_arn_prefix    = "arn:${data.aws_partition.current.partition}:eks:${local.aws_region}:${data.aws_caller_identity.current.account_id}"
}

# The Role and its EC2 instance profile remain owned by automq-console.
# This root owns only this additional inline policy and the EKS access grant.
resource "aws_iam_role_policy" "console_eks" {
  depends_on = [terraform_data.preflight]

  name = "automq-connect-eks-${substr(sha1(data.aws_eks_cluster.target.arn), 0, 12)}"
  role = local.console_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListRegionalClusters"
        Effect   = "Allow"
        Action   = ["eks:ListClusters"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = local.aws_region
          }
        }
      },
      {
        # CMP describes each regional cluster before filtering its cluster list.
        Sid      = "DescribeRegionalClusters"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "${local.eks_arn_prefix}:cluster/*"
      },
      {
        Sid      = "InspectTargetCluster"
        Effect   = "Allow"
        Action   = ["eks:ListNodegroups", "eks:ListAccessEntries"]
        Resource = data.aws_eks_cluster.target.arn
      },
      {
        Sid      = "DescribeTargetNodegroups"
        Effect   = "Allow"
        Action   = ["eks:DescribeNodegroup"]
        Resource = "${local.eks_arn_prefix}:nodegroup/${data.aws_eks_cluster.target.name}/*/*"
      },
      {
        # CMP inspects the cluster's entries to find its own runtime identity.
        Sid      = "InspectTargetAccessEntries"
        Effect   = "Allow"
        Action   = ["eks:DescribeAccessEntry", "eks:ListAssociatedAccessPolicies"]
        Resource = "${local.eks_arn_prefix}:access-entry/${data.aws_eks_cluster.target.name}/*"
      },
    ]
  })
}

resource "aws_eks_access_entry" "console" {
  depends_on = [terraform_data.preflight]

  cluster_name  = data.aws_eks_cluster.target.name
  principal_arn = local.console_role_arn
  type          = "STANDARD"

  # Keep the default STS session username used by CMP's identity check.
  tags = var.tags
}

resource "aws_eks_access_policy_association" "console" {
  cluster_name  = aws_eks_access_entry.console.cluster_name
  principal_arn = aws_eks_access_entry.console.principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  # Match CMP's EKS authorization check and the existing AWS EKS examples.
  access_scope {
    type = "cluster"
  }
}

# Successful IAM, EKS access, and ingress writes can precede runtime visibility.
# This buffer reduces first-apply races; AWS propagation can still take longer.
resource "time_sleep" "console_eks_access" {
  depends_on = [
    aws_iam_role_policy.console_eks,
    aws_eks_access_policy_association.console,
    aws_vpc_security_group_ingress_rule.console_eks_api,
    aws_vpc_security_group_ingress_rule.console_workers,
  ]

  create_duration = var.console_eks_access_wait_duration

  triggers = {
    wait_duration = var.console_eks_access_wait_duration
  }

  lifecycle {
    replace_triggered_by = [
      aws_iam_role_policy.console_eks,
      aws_eks_access_policy_association.console,
      aws_vpc_security_group_ingress_rule.console_eks_api,
      aws_vpc_security_group_ingress_rule.console_workers,
    ]
  }
}
