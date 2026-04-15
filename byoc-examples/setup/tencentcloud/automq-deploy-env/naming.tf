locals {
  alias_slug  = lower(var.alias)
  name_suffix = local.alias_slug

  # Core names
  cluster_name    = "${local.alias_slug}-tke"
  ops_bucket_name = "automq-ops-${local.alias_slug}-${data.tencentcloud_user_info.current.app_id}"

  # Network names
  vpc_name                    = "automq-vpc-${local.name_suffix}"
  public_subnet_name          = "automq-public-${local.name_suffix}"
  private_subnet_name_prefix  = "automq-private-${local.name_suffix}"
  public_route_table_name     = "automq-rtb-public-${local.name_suffix}"
  private_route_table_name    = "automq-rtb-private-${local.name_suffix}"
  nat_eip_name                = "automq-nat-eip-${local.name_suffix}"
  nat_gateway_name            = "automq-nat-${local.name_suffix}"
  cluster_security_group_name = "automq-tke-sg-${local.name_suffix}"
  cluster_security_group_desc = "Security group for automq TKE cluster ${local.cluster_name}"

  # Node pool names
  system_node_pool_name = "system-nodepool-${local.name_suffix}"

  # DNS & CAM & Data bucket
  console_dns_zone_domain = "${local.alias_slug}.automq.private.cloud"
  cluster_role_name       = "automq-kafka-role-${local.alias_slug}"
  cluster_policy_name     = "automq-kafka-policy-${local.alias_slug}"
  data_bucket_name        = "automq-data-${local.alias_slug}-${data.tencentcloud_user_info.current.app_id}"
}
