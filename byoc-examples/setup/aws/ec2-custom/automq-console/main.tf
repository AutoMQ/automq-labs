resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

resource "random_password" "console_initial_access_key" {
  length  = 16
  special = false
}

resource "random_password" "console_initial_secret_key" {
  length  = 32
  special = false
}

resource "tls_private_key" "console" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

locals {
  name_suffix        = "${var.name_prefix}-${random_string.suffix.result}"
  data_bucket_name   = trimspace(var.data_bucket_name) != "" ? var.data_bucket_name : "automq-data-${var.region}-${local.name_suffix}"
  create_data_bucket = trimspace(var.data_bucket_name) == ""
  private_key_path   = "${pathexpand(var.private_key_directory)}/automq-console-${local.name_suffix}.pem"
  broker_networks = [
    for zone in sort(keys(var.private_subnet_ids_by_zone)) : {
      zone    = zone
      subnets = var.private_subnet_ids_by_zone[zone]
    }
  ]
  common_tags = merge(var.tags, {
    ManagedBy           = "terraform"
    automqVendor        = "automq"
    automqEnvironmentID = var.environment_id
  })
  environment_file_base64 = base64encode(join("\n", [
    "ENVIRONMENT_ID=${var.environment_id}",
    "CLIENT_ID=${var.client_id}",
    "CLIENT_SECRET=${var.client_secret}",
    "CLOUD_PROVIDER=aws",
    "REGION=${var.region}",
    "CONSOLE_INITIAL_ACCESS_KEY=${random_password.console_initial_access_key.result}",
    "CONSOLE_INITIAL_SECRET_KEY=${random_password.console_initial_secret_key.result}",
    "OPS_BUCKET=${var.ops_bucket_name}",
    "ENABLE_USER_MANAGED_IAM=true",
    "IAAS_SPOT_MODE=NONE",
    "",
  ]))
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_subnet" "public" {
  id = var.public_subnet_id
}

data "aws_ami" "console" {
  most_recent = true
  owners      = var.console_ami_owners

  filter {
    name   = "name"
    values = [var.console_ami_name]
  }

  filter {
    name   = "state"
    values = ["available"]
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
    vpc_id = var.vpc_id
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
  ops_bucket_name  = var.ops_bucket_name
  hosted_zone_id   = aws_route53_zone.private.zone_id
  tags             = local.common_tags
}

resource "local_sensitive_file" "console_private_key" {
  content         = tls_private_key.console.private_key_pem
  filename        = local.private_key_path
  file_permission = "0600"
}

resource "aws_key_pair" "console" {
  key_name   = "automq-console-${local.name_suffix}"
  public_key = tls_private_key.console.public_key_openssh
  tags       = local.common_tags
}

resource "aws_security_group" "console" {
  name        = "automq-console-${local.name_suffix}"
  description = "AutoMQ Console access"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "automq-console-${local.name_suffix}"
  })
}

resource "aws_vpc_security_group_ingress_rule" "console_ui" {
  for_each = toset(var.console_allowed_cidr_blocks)

  security_group_id = aws_security_group.console.id
  description       = "AutoMQ Console UI"
  cidr_ipv4         = each.value
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.ssh_allowed_cidr_blocks)

  security_group_id = aws_security_group.console.id
  description       = "AutoMQ Console SSH"
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.console.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "console" {
  ami                         = data.aws_ami.console.id
  instance_type               = var.console_instance_type
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.console.id]
  iam_instance_profile        = aws_iam_instance_profile.console.name
  key_name                    = aws_key_pair.console.key_name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/userdata.tftpl", {
    environment_file_base64 = local.environment_file_base64
  })

  tags = merge(local.common_tags, {
    Name = "automq-console-${local.name_suffix}"
  })

  depends_on = [aws_iam_role_policy_attachment.console]
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

resource "aws_ebs_volume" "console_data" {
  availability_zone = data.aws_subnet.public.availability_zone
  size              = 20
  type              = "gp3"
  encrypted         = true

  tags = merge(local.common_tags, {
    Name = "automq-console-data-${local.name_suffix}"
  })
}

resource "aws_volume_attachment" "console_data" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.console_data.id
  instance_id = aws_instance.console.id
}
