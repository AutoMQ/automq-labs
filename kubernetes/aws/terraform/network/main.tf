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

module "vpc" {
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


resource "aws_security_group" "vpc_endpoint_sg" {
  description = "Security group for VPC endpoint"
  vpc_id      = module.vpc.vpc_id

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
  vpc_id             = module.vpc.vpc_id
  service_name       = "com.amazonaws.${var.region}.ec2"
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_security_group.vpc_endpoint_sg.id]
  subnet_ids         = module.vpc.private_subnets

  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = local.ec2_endpoint_name
  })
}

resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    module.vpc.public_route_table_ids,
    module.vpc.private_route_table_ids
  )

  tags = merge(local.tags, {
    Name = local.s3_endpoint_name
  })
}

