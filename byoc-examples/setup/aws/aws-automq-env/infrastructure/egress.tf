locals {
  private_route_table_ids = toset([for table in data.aws_route_table.private : table.id])
  private_default_routes = {
    for az, table in data.aws_route_table.private : az => [for route in table.routes : route if route.cidr_block == "0.0.0.0/0"]
  }
  existing_private_egress = alltrue([for routes in local.private_default_routes : anytrue([for route in routes : (
    try(startswith(route.nat_gateway_id, "nat-"), false) ||
    try(startswith(route.transit_gateway_id, "tgw-"), false) ||
    try(startswith(route.network_interface_id, "eni-"), false) ||
    try(startswith(route.instance_id, "i-"), false) ||
    try(startswith(route.vpc_endpoint_id, "vpce-"), false) ||
    try(length(route.core_network_arn) > 0, false)
  )])])
}

data "aws_subnet" "nat_public" {
  count = var.create_private_nat_egress ? 1 : 0
  id    = var.nat_public_subnet_id
}

data "aws_route_table" "nat_public" {
  count     = var.create_private_nat_egress ? 1 : 0
  subnet_id = var.nat_public_subnet_id
}

data "aws_internet_gateway" "nat_public" {
  count = var.create_private_nat_egress ? 1 : 0
  filter {
    name   = "attachment.vpc-id"
    values = [var.vpc_id]
  }
}

resource "terraform_data" "nat_placement" {
  count = var.create_private_nat_egress ? 1 : 0
  lifecycle {
    precondition {
      condition = data.aws_subnet.nat_public[0].vpc_id == var.vpc_id && startswith(data.aws_subnet.nat_public[0].availability_zone, local.region) && data.aws_route_table.nat_public[0].vpc_id == var.vpc_id && anytrue([
        for attachment in data.aws_internet_gateway.nat_public[0].attachments : attachment.vpc_id == var.vpc_id && attachment.state == "available"
        ]) && anytrue([
        for route in data.aws_route_table.nat_public[0].routes : route.cidr_block == "0.0.0.0/0" && route.gateway_id == data.aws_internet_gateway.nat_public[0].id
      ])
      error_message = "Optional NAT requires a same-VPC public subnet whose default route targets an attached, available Internet Gateway. This check does not prove end-to-end egress."
    }
  }
}

resource "aws_eip" "private_nat" {
  count      = var.create_private_nat_egress ? 1 : 0
  domain     = "vpc"
  tags       = merge(local.tags, { Name = "${var.name_prefix}-private-egress" })
  depends_on = [terraform_data.network_contract, terraform_data.nat_placement]
}

# A single NAT is an explicit evaluation tradeoff, not a multi-AZ egress SLA.
resource "aws_nat_gateway" "private" {
  count         = var.create_private_nat_egress ? 1 : 0
  allocation_id = aws_eip.private_nat[0].id
  subnet_id     = var.nat_public_subnet_id
  tags          = merge(local.tags, { Name = "${var.name_prefix}-private-egress" })
  depends_on    = [terraform_data.network_contract, terraform_data.nat_placement]
}

resource "terraform_data" "egress_contract" {
  lifecycle {
    precondition {
      # On repeat plans the route owned by this state is valid and retained.
      # On a first apply, NAT.id may be unknown until creation. A foreign-route
      # conflict can therefore leave this example's NAT/EIP for explicit cleanup.
      condition = var.create_private_nat_egress ? alltrue([
        for routes in local.private_default_routes : length(routes) == 0 || alltrue([
          for route in routes : route.nat_gateway_id == aws_nat_gateway.private[0].id
        ])
      ]) : local.existing_private_egress
      error_message = "Private subnets require working egress. With create_private_nat_egress=false provide an existing NAT/transit/appliance default route. Opt-in NAT can only add missing routes or retain this state's own NAT routes; it must not adopt/overwrite a foreign default. A deferred conflict may leave the new NAT/EIP to clean up."
    }
  }
}

# Stable route-table IDs are deduplicated. Never filter these resources out just
# because a later read sees the default route created by the previous apply.
resource "aws_route" "private_nat" {
  for_each               = var.create_private_nat_egress ? local.private_route_table_ids : toset([])
  route_table_id         = each.key
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.private[0].id
  depends_on             = [terraform_data.egress_contract]
}
