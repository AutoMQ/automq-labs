terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "> 5.0.0"
    }
  }
  required_version = "~> 1.3"
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available_azs" {
}

# Data source for existing VPC (only used when use_existing_vpc is true)
data "aws_vpc" "existing" {
  count = var.use_existing_vpc ? 1 : 0
  id    = var.existing_vpc_id
}

# Data sources for existing subnets
data "aws_subnet" "existing_private" {
  count = var.use_existing_vpc ? length(var.existing_private_subnet_ids) : 0
  id    = var.existing_private_subnet_ids[count.index]
}

data "aws_subnet" "existing_public" {
  count = var.use_existing_vpc ? length(var.existing_public_subnet_ids) : 0
  id    = var.existing_public_subnet_ids[count.index]
}

# Data source for route tables associated with existing subnets
data "aws_route_tables" "existing_vpc_route_tables" {
  count  = var.use_existing_vpc ? 1 : 0
  vpc_id = var.existing_vpc_id
}

# Data source to get route table for each private subnet
data "aws_route_table" "private_subnet_rt" {
  count     = var.use_existing_vpc && var.create_nat_gateway ? length(var.existing_private_subnet_ids) : 0
  subnet_id = var.existing_private_subnet_ids[count.index]
}

resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

locals {
  name_suffix       = "${random_string.suffix.result}-${var.resource_suffix}"
  vpc_name          = "vpc-${local.name_suffix}"
  endpoint_sg_name  = "endpoint-sg-${local.name_suffix}"
  ec2_endpoint_name = "ec2-endpoint-${local.name_suffix}"
  s3_endpoint_name  = "s3-endpoint-${local.name_suffix}"
  tags = {
    ManagedBy = "terraform"
  }
}

# Create new VPC only when not using existing VPC
module "vpc" {
  count  = var.use_existing_vpc ? 0 : 1
  source = "terraform-aws-modules/vpc/aws"

  cidr = "10.0.0.0/16"
  name = local.vpc_name

  azs             = slice(data.aws_availability_zones.available_azs.names, 0, 3)
  public_subnets  = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
  private_subnets = ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20"]

  enable_dns_support   = true
  enable_dns_hostnames = true

  # NAT Gateway 
  # if the deploy type is k8s, then enable_nat_gateway is true, single_nat_gateway is true
  enable_nat_gateway = true
  single_nat_gateway = true

  tags = local.tags
}


# NAT Gateway resources for existing VPC
# Create Elastic IP for NAT Gateway (only when using existing VPC and create_nat_gateway is true)
resource "aws_eip" "nat_gateway_eip" {
  count  = var.use_existing_vpc && var.create_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = merge(local.tags, {
    Name = "nat-eip-${local.name_suffix}"
  })
}

# Create NAT Gateway in the first public subnet (only when using existing VPC and create_nat_gateway is true)
resource "aws_nat_gateway" "nat_gateway" {
  count         = var.use_existing_vpc && var.create_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat_gateway_eip[0].id
  subnet_id     = var.existing_public_subnet_ids[0]

  tags = merge(local.tags, {
    Name = "nat-gateway-${local.name_suffix}"
  })

  depends_on = [aws_eip.nat_gateway_eip]
}

# Update route tables for private subnets to use NAT Gateway
resource "aws_route" "private_nat_gateway" {
  count                  = var.use_existing_vpc && var.create_nat_gateway ? length(var.existing_private_subnet_ids) : 0
  route_table_id         = data.aws_route_table.private_subnet_rt[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway[0].id

  depends_on = [aws_nat_gateway.nat_gateway]
}


resource "aws_security_group" "vpc_endpoint_sg" {
  description = "Security group for VPC endpoint"
  vpc_id      = var.use_existing_vpc ? var.existing_vpc_id : module.vpc[0].vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = local.endpoint_sg_name
  })
}


resource "aws_vpc_endpoint" "ec2_endpoint" {
  vpc_id             = var.use_existing_vpc ? var.existing_vpc_id : module.vpc[0].vpc_id
  service_name       = "com.amazonaws.${var.region}.ec2"
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_security_group.vpc_endpoint_sg.id]
  subnet_ids         = var.use_existing_vpc ? var.existing_private_subnet_ids : module.vpc[0].private_subnets

  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = local.ec2_endpoint_name
  })
}

resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id            = var.use_existing_vpc ? var.existing_vpc_id : module.vpc[0].vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = var.use_existing_vpc ? data.aws_route_tables.existing_vpc_route_tables[0].ids : concat(
    module.vpc[0].public_route_table_ids,
    module.vpc[0].private_route_table_ids
  )

  tags = merge(local.tags, {
    Name = local.s3_endpoint_name
  })
}

