locals {
  alias_slug  = lower(var.alias)
  name_suffix = local.alias_slug

  # Core names
  cluster_name    = "${local.alias_slug}-tke"
  ops_bucket_name = "automq-ops-${local.alias_slug}-${data.tencentcloud_user_info.current.app_id}"

  # Security group
  cluster_security_group_name = "automq-tke-sg-${local.name_suffix}"
  cluster_security_group_desc = "Security group for automq TKE cluster ${local.cluster_name}"

  # Node pool names
  system_node_pool_name = "system-nodepool-${local.name_suffix}"

  # DNS & CAM & Data bucket
  console_dns_zone_domain = "${local.alias_slug}.automq.private.cloud"
  cluster_role_name       = "automq-kafka-role-${local.alias_slug}"
  cluster_policy_name     = "automq-kafka-policy-${local.alias_slug}"
  data_bucket_name        = "automq-data-${local.alias_slug}-${data.tencentcloud_user_info.current.app_id}"

  # Console naming
  console_name             = "automq-console-${local.name_suffix}"
  console_policy_name      = "${local.console_name}-policy"
  console_instance_name    = local.console_name
  console_data_disk_name   = "${local.console_name}-data"
  console_private_key_path = "${pathexpand("~/.ssh")}/${local.console_name}.pem"
  console_key_pair_name    = "console_${replace(local.name_suffix, "-", "_")}"
}
