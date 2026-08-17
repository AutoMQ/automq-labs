mock_provider "aws" {
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/automq-test"
    }
  }

  mock_data "aws_vpc" {
    defaults = {
      id = "vpc-example"
    }
  }

  mock_data "aws_subnet" {
    defaults = {
      id                = "subnet-public"
      availability_zone = "us-east-1a"
    }
  }

  mock_data "aws_ami" {
    defaults = {
      id   = "ami-example"
      name = "AutoMQ-control-center-example-x86_64"
    }
  }
}

mock_provider "local" {}

mock_provider "random" {
  mock_resource "random_string" {
    defaults = {
      result = "abcde"
    }
  }

  mock_resource "random_password" {
    defaults = {
      result = "generated-secret"
    }
  }
}

mock_provider "tls" {
  mock_resource "tls_private_key" {
    defaults = {
      private_key_pem    = "private-key"
      public_key_openssh = "ssh-rsa public-key"
    }
  }
}

variables {
  name_prefix     = "automq-ec2-demo"
  region          = "us-east-1"
  environment_id  = "env-example"
  client_id       = "client-example"
  client_secret   = "client-secret"
  ops_bucket_name = "automq-ops-example"

  vpc_id           = "vpc-example"
  public_subnet_id = "subnet-public"
  private_subnet_ids_by_zone = {
    us-east-1a = ["subnet-a"]
    us-east-1b = ["subnet-b"]
    us-east-1c = ["subnet-c"]
  }

  console_ami_name   = "AutoMQ-control-center-example-x86_64"
  console_ami_owners = ["self"]

  console_allowed_cidr_blocks = ["203.0.113.10/32"]
  ssh_allowed_cidr_blocks     = ["203.0.113.10/32"]
}

run "console_and_data_plane_roles_are_separate" {
  command = apply

  assert {
    condition     = aws_iam_role.console.name != module.automq_role.role_name
    error_message = "The Console and AutoMQ data-plane nodes must use separate IAM roles."
  }

  assert {
    condition     = strcontains(aws_iam_policy.console.policy, module.automq_role.role_arn)
    error_message = "The Console PassRole permission must reference the dedicated data-plane role."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.console_ui) == 1 && length(aws_vpc_security_group_ingress_rule.ssh) == 1
    error_message = "Only explicitly configured Console and SSH CIDRs should create ingress rules."
  }

  assert {
    condition     = output.broker_networks[0].zone == "us-east-1a" && output.broker_networks[2].zone == "us-east-1c"
    error_message = "Broker networks must be deterministically sorted by availability zone."
  }
}

run "empty_console_allowlist_is_rejected" {
  command = plan

  variables {
    console_allowed_cidr_blocks = []
  }

  expect_failures = [var.console_allowed_cidr_blocks]
}

run "empty_ssh_allowlist_is_rejected" {
  command = plan

  variables {
    ssh_allowed_cidr_blocks = []
  }

  expect_failures = [var.ssh_allowed_cidr_blocks]
}
