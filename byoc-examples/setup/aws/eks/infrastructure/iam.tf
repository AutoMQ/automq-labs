locals {
  issuer = trimprefix(module.eks_cluster.cluster_oidc_issuer_url, "https://")
  pod_subjects = {
    console = "system:serviceaccount:${var.console_namespace}:${var.console_service_account_name}"
  }
  managed_bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::automq-data-kf-*"
  managed_role_arn   = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/automq-instance-kf-*"
  managed_policy_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/automq-*-kf-*"
}

resource "aws_iam_role" "pod" {
  for_each = local.pod_subjects
  name     = "${var.name_prefix}-${each.key}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = module.eks_cluster.oidc_provider_arn }
      Condition = { StringEquals = { "${local.issuer}:aud" = "sts.amazonaws.com", "${local.issuer}:sub" = each.value } }
    }]
  })
  tags = local.tags
}

# List/Describe discovery APIs below cannot all be scoped to an individual ARN.
# Mutation is separated and restricted to the Ops bucket or CMP naming patterns.
resource "aws_iam_role_policy" "console_discovery" {
  name = "${var.name_prefix}-console-discovery"
  role = aws_iam_role.pod["console"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid = "DiscoverAndCheck", Effect = "Allow", Resource = "*"
      Action = [
        "ec2:DescribeAvailabilityZones", "ec2:DescribeVpcs", "ec2:DescribeSubnets", "ec2:DescribeRouteTables", "ec2:DescribeVpcEndpoints", "ec2:DescribeSecurityGroups", "ec2:DescribeVolumes", "ec2:DescribeInstances", "ec2:DescribeInstanceTypes", "ec2:DescribeInstanceTypeOfferings", "ec2:DescribeTags",
        "eks:ListClusters", "eks:DescribeCluster", "eks:ListNodegroups", "eks:DescribeNodegroup", "eks:ListAccessEntries", "eks:DescribeAccessEntry", "eks:ListAssociatedAccessPolicies", "eks:ListPodIdentityAssociations", "eks:DescribePodIdentityAssociation",
        "s3:ListAllMyBuckets", "route53:ListHostedZones", "route53:ListHostedZonesByName", "route53:ListHostedZonesByVPC", "elasticloadbalancing:DescribeTargetGroups",
        "iam:GetRole", "iam:GetRolePolicy", "iam:ListRoles", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyTags", "iam:ListPolicyVersions", "iam:ListOpenIDConnectProviders", "iam:GetOpenIDConnectProvider", "iam:GetInstanceProfile", "iam:ListInstanceProfilesForRole"
      ]
    }]
  })
}

resource "aws_iam_role_policy" "console_managed" {
  name = "${var.name_prefix}-console-managed"
  role = aws_iam_role.pod["console"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "OpsBucketMetadata", Effect = "Allow", Resource = aws_s3_bucket.ops.arn
        Action = ["s3:CreateBucket", "s3:ListBucket", "s3:GetBucketLocation", "s3:GetBucketPolicy", "s3:PutBucketPolicy", "s3:GetBucketTagging", "s3:PutBucketTagging", "s3:GetLifecycleConfiguration", "s3:PutLifecycleConfiguration", "s3:ListBucketMultipartUploads"]
      },
      {
        Sid    = "OpsObjects", Effect = "Allow", Resource = "${aws_s3_bucket.ops.arn}/*"
        Action = ["s3:GetObject", "s3:PutObject", "s3:PutObjectTagging", "s3:DeleteObject", "s3:AbortMultipartUpload"]
      },
      {
        Sid    = "ManagedDataBuckets", Effect = "Allow", Resource = local.managed_bucket_arn
        Action = ["s3:CreateBucket", "s3:DeleteBucket", "s3:ListBucket", "s3:GetBucketLocation", "s3:GetBucketTagging", "s3:PutBucketTagging", "s3:GetLifecycleConfiguration", "s3:ListBucketMultipartUploads"]
      },
      {
        Sid    = "ManagedDataCleanup", Effect = "Allow", Resource = "${local.managed_bucket_arn}/*"
        Action = ["s3:DeleteObject", "s3:AbortMultipartUpload"]
      },
      {
        # Released Console creates the role, then applies ownership tags.
        # Creation stays scoped to this account and CMP's Instance role names.
        Sid    = "CreateManagedInstanceRoles", Effect = "Allow", Resource = local.managed_role_arn
        Action = ["iam:CreateRole", "iam:TagRole"]
      },
      {
        Sid    = "ReconcileOwnedInstanceRoles", Effect = "Allow", Resource = local.managed_role_arn
        Action = ["iam:UntagRole", "iam:DeleteRole", "iam:UpdateAssumeRolePolicy"]
        Condition = {
          StringEquals = { "aws:ResourceTag/automqVendor" = "automq" }
          StringLike   = { "aws:ResourceTag/automqInstanceID" = "kf-*" }
        }
      },
      {
        Sid    = "AttachInstancePolicies", Effect = "Allow", Resource = local.managed_role_arn
        Action = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
        Condition = {
          StringEquals = { "aws:ResourceTag/automqVendor" = "automq" }
          StringLike   = { "aws:ResourceTag/automqInstanceID" = "kf-*" }
          ArnLike      = { "iam:PolicyARN" = local.managed_policy_arn }
        }
      },
      {
        Sid    = "ManagedInstancePolicies", Effect = "Allow", Resource = local.managed_policy_arn
        Action = ["iam:CreatePolicy", "iam:TagPolicy", "iam:UntagPolicy", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:DeletePolicy"]
      },
      # Hosted zone IDs do not exist until CMP creates them; this evaluation
      # Default Permissions envelope is broader than the per-Instance runtime role.
      {
        Sid    = "CreateManagedPrivateDns", Effect = "Allow", Resource = "*"
        Action = ["route53:CreateHostedZone"]
      },
      {
        Sid    = "ManagePrivateDns", Effect = "Allow", Resource = "arn:${data.aws_partition.current.partition}:route53:::hostedzone/*"
        Action = ["route53:GetHostedZone", "route53:DeleteHostedZone", "route53:ChangeTagsForResource", "route53:ListTagsForResource", "route53:ListResourceRecordSets", "route53:ChangeResourceRecordSets"]
      }
    ]
  })
}
