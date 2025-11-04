terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "random_id" "suffix" {
  byte_length = 4
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_rds_engine_version" "mysql" {
  count                  = var.database_type == "mysql" ? 1 : 0
  engine                 = "mysql"
  parameter_group_family = "mysql8.0"
  default_only           = true
}

data "aws_rds_engine_version" "postgresql" {
  count                  = var.database_type == "postgresql" ? 1 : 0
  engine                 = "postgres"
  parameter_group_family = "postgres15"
  default_only           = true
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnet_cidrs = [
    "10.0.1.0/24",
    "10.0.2.0/24",
  ]
  tags = {
    Environment = "debezium-test"
  }
  db_port        = var.database_type == "mysql" ? 3306 : 5432
  engine         = var.database_type == "mysql" ? "mysql" : "postgres"
  engine_version = var.database_type == "mysql" ? data.aws_rds_engine_version.mysql[0].version : data.aws_rds_engine_version.postgresql[0].version
  instance_class = "db.t3.micro"
  identifier     = "debezium-${var.database_type}-${random_id.suffix.hex}"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, {
    Name = "debezium-vpc-${random_id.suffix.hex}"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "debezium-igw-${random_id.suffix.hex}"
  })
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "debezium-public-${count.index + 1}-${random_id.suffix.hex}"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.tags, {
    Name = "debezium-public-rt-${random_id.suffix.hex}"
  })
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "db" {
  name        = "debezium-db-${random_id.suffix.hex}"
  description = "Allow database access for Debezium testing"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol    = "tcp"
    from_port   = local.db_port
    to_port     = local.db_port
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "debezium-db-sg-${random_id.suffix.hex}"
  })
}

resource "aws_db_subnet_group" "main" {
  name       = "debezium-db-subnet-${random_id.suffix.hex}"
  subnet_ids = aws_subnet.public[*].id

  tags = merge(local.tags, {
    Name = "debezium-db-subnet-${random_id.suffix.hex}"
  })
}

resource "aws_db_parameter_group" "mysql" {
  count  = var.database_type == "mysql" ? 1 : 0
  name   = "debezium-mysql-${random_id.suffix.hex}"
  family = "mysql8.0"

  parameter {
    name         = "binlog_format"
    value        = "ROW"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "binlog_row_image"
    value        = "FULL"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "binlog_checksum"
    value        = "NONE"
    apply_method = "pending-reboot"
  }

  tags = merge(local.tags, {
    Name = "debezium-mysql-${random_id.suffix.hex}"
  })
}

resource "aws_db_parameter_group" "postgresql" {
  count  = var.database_type == "postgresql" ? 1 : 0
  name   = "debezium-postgres-${random_id.suffix.hex}"
  family = "postgres15"

  parameter {
    name  = "rds.logical_replication"
    value = "1"
  }

  parameter {
    name  = "wal_level"
    value = "logical"
  }

  parameter {
    name  = "max_replication_slots"
    value = "10"
  }

  parameter {
    name  = "max_wal_senders"
    value = "10"
  }

  tags = merge(local.tags, {
    Name = "debezium-postgres-${random_id.suffix.hex}"
  })
}

resource "random_password" "db" {
  length           = 20
  special          = true
  override_special = "!@#_-"
}

resource "aws_db_instance" "main" {
  identifier              = local.identifier
  engine                  = local.engine
  engine_version          = local.engine_version
  instance_class          = local.instance_class
  allocated_storage       = 20
  db_name                 = "testdb"
  username                = "admin"
  password                = random_password.db.result
  port                    = local.db_port
  publicly_accessible     = true
  skip_final_snapshot     = true
  backup_retention_period = 1
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.db.id]

  parameter_group_name = var.database_type == "mysql" ? aws_db_parameter_group.mysql[0].name : aws_db_parameter_group.postgresql[0].name

  tags = merge(local.tags, {
    Name = "${local.identifier}"
  })
}
