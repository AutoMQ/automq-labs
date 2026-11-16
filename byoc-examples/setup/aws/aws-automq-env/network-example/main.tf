data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  zones = { for index, az in var.availability_zones : az => index }
  tags  = { Project = var.name_prefix, ManagedBy = "terraform", Purpose = "automq-eks-evaluation" }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = var.name_prefix })

  lifecycle {
    precondition {
      condition     = alltrue([for az in var.availability_zones : contains(data.aws_availability_zones.available.names, az)])
      error_message = "Every selected AZ must be available in the target AWS account and region."
    }
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = local.tags
}

resource "aws_subnet" "public" {
  for_each                = local.zones
  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, each.value)
  map_public_ip_on_launch = false
  tags                    = merge(local.tags, { Name = "${var.name_prefix}-public-${each.key}", "kubernetes.io/role/elb" = "1" })
}

resource "aws_subnet" "private" {
  for_each                = local.zones
  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, each.value + 8)
  map_public_ip_on_launch = false
  tags                    = merge(local.tags, { Name = "${var.name_prefix}-private-${each.key}", "kubernetes.io/role/internal-elb" = "1" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = local.tags
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each       = local.zones
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = local.tags
}

# A single NAT is an evaluation cost tradeoff; it is not a multi-AZ egress SLA.
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[var.availability_zones[0]].id
  tags          = local.tags
  depends_on    = [aws_internet_gateway.this, aws_route.internet]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = local.tags
}

resource "aws_route" "nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "private" {
  for_each       = local.zones
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id, aws_route_table.private.id]
  # Endpoint access must allow future Console-managed data buckets as well as Ops.
  # IAM on each Pod Role, rather than this network-wide policy, grants access.
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = "*", Action = "s3:*", Resource = "*" }]
  })
  tags = local.tags
}
