resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

resource "random_password" "console_initial_password" {
  length  = 24
  special = false
}

resource "random_password" "console_initial_access_key" {
  length  = 16
  special = false
}

resource "random_password" "console_initial_secret_key" {
  length  = 32
  special = false
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "http" "caller_ip" {
  count = var.console_allowed_cidr_blocks == null ? 1 : 0
  url   = "https://checkip.amazonaws.com"
}

locals {
  automq_config = jsondecode(base64decode(var.automq_config))

  environment_id  = nonsensitive(local.automq_config.environmentId)
  region          = nonsensitive(local.automq_config.region)
  ops_bucket_name = nonsensitive(local.automq_config.opsBucket.bucketName)

  name_suffix        = "${var.name_prefix}-${random_string.suffix.result}"
  data_bucket_name   = trimspace(var.data_bucket_name) != "" ? var.data_bucket_name : "automq-data-${local.region}-${local.name_suffix}"
  create_data_bucket = trimspace(var.data_bucket_name) == ""
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 3)
  console_allowed_cidr_blocks = var.console_allowed_cidr_blocks == null ? [
    "${trimspace(data.http.caller_ip[0].response_body)}/32"
  ] : var.console_allowed_cidr_blocks
  private_subnet_ids_by_zone = {
    for index, zone in local.availability_zones : zone => [aws_subnet.broker[index].id]
  }
  broker_networks = [
    for zone in sort(keys(local.private_subnet_ids_by_zone)) : {
      zone    = zone
      subnets = local.private_subnet_ids_by_zone[zone]
    }
  ]
  common_tags = merge(var.tags, {
    ManagedBy           = "terraform"
    automqVendor        = "automq"
    automqEnvironmentID = local.environment_id
  })
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "automq-vpc-${local.name_suffix}"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "automq-igw-${local.name_suffix}"
  })
}

resource "aws_subnet" "console" {
  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.availability_zones[0]
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 0)
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "automq-console-${local.name_suffix}"
    Tier = "public"
  })
}

resource "aws_subnet" "broker" {
  count = 3

  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.availability_zones[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "automq-broker-${local.name_suffix}-${local.availability_zones[count.index]}"
    Tier = "private"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "automq-public-${local.name_suffix}"
  })
}

resource "aws_route_table_association" "console" {
  subnet_id      = aws_subnet.console.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "automq-nat-${local.name_suffix}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.console.id

  tags = merge(local.common_tags, {
    Name = "automq-nat-${local.name_suffix}"
  })

  depends_on = [aws_route_table_association.console]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "automq-private-${local.name_suffix}"
  })
}

resource "aws_route_table_association" "broker" {
  count = 3

  subnet_id      = aws_subnet.broker[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_s3_bucket" "ops" {
  bucket        = local.ops_bucket_name
  force_destroy = var.force_destroy_ops_bucket

  tags = merge(local.common_tags, {
    Name = local.ops_bucket_name
  })
}

resource "aws_s3_bucket_public_access_block" "ops" {
  bucket = aws_s3_bucket.ops.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ops" {
  bucket = aws_s3_bucket.ops.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket" "data" {
  count = local.create_data_bucket ? 1 : 0

  bucket        = local.data_bucket_name
  force_destroy = var.force_destroy_data_bucket

  tags = merge(local.common_tags, {
    Name = local.data_bucket_name
  })
}

resource "aws_s3_bucket_public_access_block" "data" {
  count = local.create_data_bucket ? 1 : 0

  bucket                  = aws_s3_bucket.data[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  count = local.create_data_bucket ? 1 : 0

  bucket = aws_s3_bucket.data[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_route53_zone" "private" {
  name          = "${local.name_suffix}.automq.private"
  force_destroy = true

  vpc {
    vpc_id = aws_vpc.this.id
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "automq-private-zone-${local.name_suffix}"
  })
}

module "automq_role" {
  source = "../modules/automq-role"

  name_prefix      = local.name_suffix
  data_bucket_name = local.data_bucket_name
  ops_bucket_name  = local.ops_bucket_name
  hosted_zone_id   = aws_route53_zone.private.zone_id
  tags             = local.common_tags
}

resource "aws_security_group" "console" {
  name        = "automq-console-${local.name_suffix}"
  description = "AutoMQ Console access"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "automq-console-${local.name_suffix}"
  })
}

resource "aws_vpc_security_group_ingress_rule" "console_ui" {
  for_each = toset(local.console_allowed_cidr_blocks)

  security_group_id = aws_security_group.console.id
  description       = "AutoMQ Console UI"
  cidr_ipv4         = each.value
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.console.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_ebs_volume" "console_data" {
  availability_zone = aws_subnet.console.availability_zone
  size              = 20
  type              = "gp3"
  encrypted         = true

  tags = merge(local.common_tags, {
    Name = "automq-console-data-${local.name_suffix}"
  })
}

resource "aws_instance" "console" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.console_instance_type
  subnet_id                   = aws_subnet.console.id
  vpc_security_group_ids      = [aws_security_group.console.id]
  iam_instance_profile        = aws_iam_instance_profile.console.name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/userdata.tftpl", {
    automq_config_b64          = base64encode(var.automq_config)
    console_image_b64          = base64encode(var.console_image)
    initial_password_b64       = base64encode(random_password.console_initial_password.result)
    initial_access_key_b64     = base64encode(random_password.console_initial_access_key.result)
    initial_secret_key_b64     = base64encode(random_password.console_initial_secret_key.result)
    console_data_volume_id_b64 = base64encode(aws_ebs_volume.console_data.id)
  })

  tags = merge(local.common_tags, {
    Name = "automq-console-${local.name_suffix}"
  })

  depends_on = [
    aws_iam_role_policy_attachment.console,
    aws_iam_role_policy_attachment.console_ssm,
    aws_nat_gateway.this,
    aws_s3_bucket.ops,
  ]
}

resource "aws_volume_attachment" "console_data" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.console_data.id
  instance_id = aws_instance.console.id
}

resource "aws_eip" "console" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "automq-console-${local.name_suffix}"
  })
}

resource "aws_eip_association" "console" {
  allocation_id = aws_eip.console.id
  instance_id   = aws_instance.console.id
}
