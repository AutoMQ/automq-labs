resource "aws_iam_role" "connect_worker" {
  depends_on = [terraform_data.preflight]

  name = var.connect_worker_role_name
  # Leave room for the provider's unique suffix within IAM's 64-character limit.
  name_prefix = var.connect_worker_role_name == null ? "${substr(var.connect_cluster_name, 0, 25)}-worker-" : null
  description = "IRSA identity for the ${var.connect_cluster_name} Connect workers"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.eks.arn
      }
      Condition = {
        StringEquals = {
          "${local.eks_oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.eks_oidc_issuer}:sub" = "system:serviceaccount:${var.connect_namespace}:${var.connect_service_account}"
        }
      }
    }]
  })

  tags = var.tags
}

# CMP stores unpacked plugin artifacts under this prefix in the environment's
# Ops Bucket. Init containers use S3 sync to download them before workers start.
resource "aws_iam_role_policy" "plugin_download" {
  name = "automq-connect-plugin-download"
  role = aws_iam_role.connect_worker.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadPluginObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${local.ops_bucket_arn}/${var.connect_plugin_s3_prefix}/*"
      },
      {
        Sid      = "ListPluginDirectory"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = local.ops_bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = [var.connect_plugin_s3_prefix, "${var.connect_plugin_s3_prefix}/*"]
          }
        }
      },
    ]
  })
}

# Additional AWS permissions are opt-in and remain scoped by the supplied policies.
resource "aws_iam_role_policy_attachment" "connect_worker" {
  for_each = var.connect_worker_policy_arns

  role       = aws_iam_role.connect_worker.name
  policy_arn = each.value
}
