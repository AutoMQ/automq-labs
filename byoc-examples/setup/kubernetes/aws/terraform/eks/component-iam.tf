data "aws_partition" "current" {}

locals {
  component_issuer = trimprefix(module.eks.cluster_oidc_issuer_url, "https://")
  component_subjects = var.component_irsa_prefix == null ? {} : {
    cni           = "system:serviceaccount:kube-system:aws-node"
    ebs-csi       = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
    lb-controller = "system:serviceaccount:kube-system:aws-load-balancer-controller"
    autoscaler    = "system:serviceaccount:kube-system:cluster-autoscaler"
  }
}

resource "aws_iam_role" "pod" {
  for_each = local.component_subjects
  name     = "${var.component_irsa_prefix}-${each.key}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Condition = { StringEquals = { "${local.component_issuer}:aud" = "sts.amazonaws.com", "${local.component_issuer}:sub" = each.value } }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "component" {
  for_each = var.component_irsa_prefix == null ? {} : {
    cni = "AmazonEKS_CNI_Policy", ebs-csi = "service-role/AmazonEBSCSIDriverPolicy"
  }
  role       = aws_iam_role.pod[each.key].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}

resource "aws_iam_role_policy" "autoscaler" {
  count = var.component_irsa_prefix == null ? 0 : 1
  name  = "${var.component_irsa_prefix}-autoscaler"
  role  = aws_iam_role.pod["autoscaler"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow", Resource = "*"
        Action = ["autoscaling:DescribeAutoScalingGroups", "autoscaling:DescribeAutoScalingInstances", "autoscaling:DescribeLaunchConfigurations", "autoscaling:DescribeScalingActivities", "autoscaling:DescribeTags", "ec2:DescribeImages", "ec2:DescribeInstanceTypes", "ec2:DescribeLaunchTemplateVersions", "ec2:GetInstanceTypesFromInstanceRequirements", "eks:DescribeNodegroup"]
      },
      {
        Effect = "Allow", Resource = "*"
        Action = ["autoscaling:SetDesiredCapacity", "autoscaling:TerminateInstanceInAutoScalingGroup"]
        Condition = { StringEquals = {
          "aws:ResourceTag/k8s.io/cluster-autoscaler/enabled"               = "true"
          "aws:ResourceTag/k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
        } }
      }
    ]
  })
}

# Vendored unmodified upstream v2.13.4 policy; use the matching controller release.
# https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v2.13.4/docs/install/iam_policy.json
resource "aws_iam_role_policy" "lb_controller" {
  count  = var.component_irsa_prefix == null ? 0 : 1
  name   = "${var.component_irsa_prefix}-lb-controller"
  role   = aws_iam_role.pod["lb-controller"].id
  policy = file("${path.module}/policies/lb-controller-v2.13.4.json")
}
