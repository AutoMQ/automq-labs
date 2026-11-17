locals {
  # Guard evaluation so invalid CONFIG produces the variable's actionable
  # validation errors before providers/resources, rather than a decode panic.
  config          = try(jsondecode(base64decode(var.automq_config)), {})
  region          = try(nonsensitive(local.config.region), "us-east-1")
  environment_id  = try(nonsensitive(local.config.environmentId), "invalid-config")
  ops_bucket_name = try(nonsensitive(local.config.opsBucket.bucketName), "invalid-config")
  cluster_name    = "${var.name_prefix}-eks"
  tags            = { Project = var.name_prefix, ManagedBy = "terraform", Purpose = "automq-eks-evaluation" }
  private_subnets = values(var.private_subnet_ids_by_az)
  automq_selector = { "automq.io/pool" = "automq" }
  automq_tolerations = [{
    key = "dedicated", operator = "Equal", value = "automq", effect = "NoSchedule"
  }]
  service_start = sum([for i, octet in split(".", cidrhost(var.service_ipv4_cidr, 0)) : tonumber(octet) * pow(256, 3 - i)])
  service_end   = sum([for i, octet in split(".", cidrhost(var.service_ipv4_cidr, -1)) : tonumber(octet) * pow(256, 3 - i)])
  vpc_cidrs     = distinct(concat([data.aws_vpc.selected.cidr_block], [for association in data.aws_vpc.selected.cidr_block_associations : association.cidr_block]))
  vpc_intervals = [for cidr in local.vpc_cidrs : {
    start = sum([for i, octet in split(".", cidrhost(cidr, 0)) : tonumber(octet) * pow(256, 3 - i)])
    end   = sum([for i, octet in split(".", cidrhost(cidr, -1)) : tonumber(octet) * pow(256, 3 - i)])
  }]
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_vpc" "selected" { id = var.vpc_id }
data "aws_subnet" "private" {
  for_each = var.private_subnet_ids_by_az
  id       = each.value
}
data "aws_route_table" "private" {
  for_each  = var.private_subnet_ids_by_az
  subnet_id = each.value
}
data "aws_vpc_endpoint" "s3" { id = var.s3_vpc_endpoint_id }
data "aws_ec2_instance_type" "system" { instance_type = var.system_instance_type }
data "aws_ec2_instance_type" "automq" { instance_type = var.automq_instance_type }

resource "terraform_data" "network_contract" {
  input = { vpc_id = var.vpc_id }
  lifecycle {
    precondition {
      condition     = alltrue([for az, subnet in data.aws_subnet.private : subnet.vpc_id == var.vpc_id && subnet.availability_zone == az && startswith(az, local.region) && !subnet.map_public_ip_on_launch])
      error_message = "Every private subnet must belong to vpc_id, match its AZ map key and CONFIG region, and disable automatic public IP assignment."
    }
    precondition {
      condition     = data.aws_vpc.selected.enable_dns_support && data.aws_vpc.selected.enable_dns_hostnames
      error_message = "The existing VPC must enable DNS support and DNS hostnames for the EKS private API."
    }
    precondition {
      condition     = alltrue([for route_table in data.aws_route_table.private : route_table.vpc_id == var.vpc_id && alltrue([for route in route_table.routes : !(try(route.cidr_block == "0.0.0.0/0" && startswith(route.gateway_id, "igw-"), false))])])
      error_message = "Selected workload subnet route tables must belong to vpc_id and must not use a direct Internet Gateway default route."
    }
    precondition {
      condition     = contains(data.aws_ec2_instance_type.system.supported_architectures, "x86_64") && data.aws_ec2_instance_type.system.memory_size >= 8192 && data.aws_ec2_instance_type.system.default_vcpus >= 2 && contains(data.aws_ec2_instance_type.automq.supported_architectures, "arm64")
      error_message = "System nodes require x86_64, at least 2 vCPUs and 8 GiB for Console plus infrastructure; AutoMQ nodes require ARM64 for the configured AL2023 AMI."
    }
    precondition {
      condition     = alltrue([for range in local.vpc_intervals : local.service_end < range.start || local.service_start > range.end])
      error_message = "service_ipv4_cidr must not overlap any IPv4 CIDR associated with the selected VPC."
    }
    precondition {
      condition     = data.aws_vpc_endpoint.s3.vpc_id == var.vpc_id && data.aws_vpc_endpoint.s3.vpc_endpoint_type == "Gateway" && data.aws_vpc_endpoint.s3.service_name == "com.amazonaws.${local.region}.s3" && alltrue([for route_table in data.aws_route_table.private : contains(data.aws_vpc_endpoint.s3.route_table_ids, route_table.id)])
      error_message = "s3_vpc_endpoint_id must be the same-region S3 Gateway Endpoint in vpc_id and cover every selected subnet route table."
    }
    precondition {
      condition     = split(":", var.deployer_role_arn)[4] == data.aws_caller_identity.current.account_id
      error_message = "deployer_role_arn must belong to the target AWS account."
    }
    precondition {
      condition     = data.aws_vpc.selected.owner_id == data.aws_caller_identity.current.account_id
      error_message = "The selected VPC must belong to the target AWS account; cross-account/shared VPC setup is outside this example."
    }
  }
}

resource "aws_s3_bucket" "ops" {
  bucket        = local.ops_bucket_name
  force_destroy = false
  tags          = merge(local.tags, { AutoMQEnvironmentID = local.environment_id })
  depends_on    = [terraform_data.network_contract]
}

resource "aws_s3_bucket_public_access_block" "ops" {
  bucket                  = aws_s3_bucket.ops.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ops" {
  bucket = aws_s3_bucket.ops.id
  rule {
    blocked_encryption_types = ["SSE-C"]
    bucket_key_enabled       = false
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
