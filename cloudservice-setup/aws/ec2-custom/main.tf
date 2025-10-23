terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "> 5.0"
    }
  }
  required_version = "~> 1.3"
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available_azs" {}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_subnet" "public" {
  id = var.public_subnet_id
}

module "automq_byoc_data_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket        = local.data_bucket_name
  force_destroy = true

  create_bucket = local.create_data_bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  tags = merge(local.common_tags, {
    Name = "automq-data-${local.env_id}"
  })
}

module "automq_byoc_ops_bucket_name" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket        = local.ops_bucket_name
  force_destroy = true

  create_bucket = local.create_ops_bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  tags = merge(local.common_tags, {
    Name = "automq-ops-${local.env_id}"
  })
}

resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.key_pair.private_key_pem
  filename        = "${pathexpand("~/.ssh")}/automq-console-${local.env_id}.pem"
  file_permission = "0600"
}

resource "aws_key_pair" "key_pair" {
  key_name   = "automq-console-${local.env_id}"
  public_key = tls_private_key.key_pair.public_key_openssh
}

data "aws_ami" "console_ami" {
  most_recent = true
  # owners      = ["self"]
  allow_unsafe_filter = true

  filter {
    name   = "name"
    values = [var.image_name]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_security_group" "automq_byoc_console_sg" {
  name   = "automq-byoc-console-sg-${local.env_id}"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "automq-byoc-console-sg-${local.env_id}"
  })
}

resource "aws_eip" "web_ip" {
  instance = aws_instance.automq_byoc_console.id
  tags     = local.common_tags
}

resource "aws_instance" "automq_byoc_console" {
  ami                         = data.aws_ami.console_ami.id
  instance_type               = var.automq_byoc_ec2_instance_type
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.automq_byoc_console_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.automq_byoc_instance_profile.name
  key_name                    = aws_key_pair.key_pair.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/userdata.tpl", {
    aws_iam_instance_profile_arn_encoded = urlencode(aws_iam_instance_profile.automq_byoc_instance_profile.arn),
    automq_data_bucket                   = local.data_bucket_name,
    automq_ops_bucket                    = local.ops_bucket_name,
    instance_security_group_id           = aws_security_group.automq_byoc_console_sg.id,
    instance_dns                         = aws_route53_zone.private_r53.zone_id,
    instance_profile_arn                 = aws_iam_instance_profile.automq_byoc_instance_profile.arn,
    environment_id                       = local.env_id
  })

  tags = merge(local.common_tags, {
    Name = "automq-byoc-console-${local.env_id}"
  })
}

resource "aws_ebs_volume" "data_volume" {
  availability_zone = data.aws_subnet.public.availability_zone
  size              = 20
  type              = "gp3"

  tags = merge(local.common_tags, {
    Name = "automq-console-data-${local.env_id}"
  })
}

resource "aws_volume_attachment" "data_volume_attachment" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.data_volume.id
  instance_id = aws_instance.automq_byoc_console.id
}

resource "aws_route53_zone" "private_r53" {
  name = "${local.name_suffix}.automq.private"

  vpc {
    vpc_id = var.vpc_id
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "automq-private-zone-${local.env_id}"
  })
}