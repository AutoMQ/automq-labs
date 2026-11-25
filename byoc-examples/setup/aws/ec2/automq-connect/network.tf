locals {
  eks_vpc_id                   = try(data.aws_eks_cluster.target.vpc_config[0].vpc_id, "")
  eks_api_security_group_id    = try(data.aws_eks_cluster.target.vpc_config[0].cluster_security_group_id, "")
  eks_api_security_group_valid = can(regex("^sg-([0-9a-f]{8}|[0-9a-f]{17})$", local.eks_api_security_group_id))
  connect_worker_security_group_ids = length(var.connect_worker_security_group_ids) > 0 ? var.connect_worker_security_group_ids : (
    local.eks_api_security_group_valid ? toset([local.eks_api_security_group_id]) : toset([])
  )
}

data "aws_security_group" "console" {
  count = local.console_security_group_valid ? 1 : 0

  id = local.console_security_group_id
}

data "aws_security_group" "workers" {
  for_each = local.connect_worker_security_group_ids

  id = each.value
}

# Manage only these additional ingress rules; EKS retains its security groups
# and default rules. Console egress and other network paths remain external.
resource "aws_vpc_security_group_ingress_rule" "console_eks_api" {
  depends_on = [terraform_data.preflight]

  # Fallbacks allow preflight to report missing state or metadata clearly.
  security_group_id            = local.eks_api_security_group_valid ? local.eks_api_security_group_id : "sg-00000000000000000"
  referenced_security_group_id = local.console_security_group_valid ? local.console_security_group_id : "sg-00000000000000000"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "AutoMQ Console to private EKS API"

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "console_workers" {
  for_each = local.connect_worker_security_group_ids

  depends_on = [terraform_data.preflight]

  security_group_id            = each.value
  referenced_security_group_id = local.console_security_group_valid ? local.console_security_group_id : "sg-00000000000000000"
  ip_protocol                  = "tcp"
  from_port                    = 8083
  to_port                      = 8083
  description                  = "AutoMQ Console to Connect worker REST"

  tags = var.tags
}
