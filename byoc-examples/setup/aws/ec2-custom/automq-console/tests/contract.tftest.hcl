mock_provider "aws" {
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/automq-test"
    }
  }

  mock_resource "aws_route53_zone" {
    defaults = {
      zone_id = "Z0123456789"
    }
  }

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }

  mock_data "aws_ssm_parameter" {
    defaults = {
      value = "ami-example"
    }
  }
}

mock_provider "http" {
  mock_data "http" {
    defaults = {
      response_body = "203.0.113.10\n"
    }
  }
}

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

variables {
  automq_config = base64encode(jsonencode({
    environmentId = "env-example"
    clientId      = "env-example"
    clientSecret  = "client-secret"
    region        = "us-east-1"
    opsBucket = {
      bucketName = "automq-ops-example"
    }
  }))
}

run "console_stack_is_self_contained" {
  command = apply

  assert {
    condition     = output.environment_id == "env-example" && output.region == "us-east-1"
    error_message = "Environment ID and Region must be decoded from the single CONFIG input."
  }

  assert {
    condition     = aws_iam_role.console.name != module.automq_role.role_name
    error_message = "The Console and AutoMQ data-plane nodes must use separate IAM roles."
  }

  assert {
    condition = one([
      for statement in jsondecode(aws_iam_policy.console.policy).Statement : statement
      if statement.Sid == "PassAutoMQDataPlaneRole"
      ]).Resource == "*" && one([
      for statement in jsondecode(aws_iam_policy.console.policy).Statement : statement
      if statement.Sid == "PassAutoMQDataPlaneRole"
    ]).Condition.StringLike["iam:PassedToService"] == "ec2.amazonaws.com*"
    error_message = "The Console PassRole permission must satisfy the EC2 initialization check and restrict the target service to EC2."
  }

  assert {
    condition = alltrue([
      for action in [
        "autoscaling:CreateOrUpdateTags",
        "autoscaling:DeleteTags",
        "ec2:DeleteTags",
        "elasticfilesystem:CreateFileSystem",
        "elasticfilesystem:DeleteFileSystem",
        "fsx:CreateFileSystem",
        "fsx:DeleteFileSystem",
        "iam:GetInstanceProfile",
        "iam:GetPolicy",
        "iam:GetRole",
        "iam:GetRolePolicy",
        "iam:GetPolicyVersion",
        "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfilesForRole",
        "iam:ListRolePolicies",
        "iam:ListRoles",
        "route53:ListHostedZonesByVpc",
        "s3:GetBucketLocation",
        "s3:GetBucketTagging",
        "s3:GetLifecycleConfiguration",
        "s3:ListAllMyBuckets",
        "s3:ListBucket",
        "sts:AssumeRole",
      ] : strcontains("${aws_iam_policy.console.policy}${aws_iam_policy.console_compute.policy}", action)
    ])
    error_message = "The Console policies must satisfy the Console 8.3.16 EC2 minimal initialization and instance-validation contracts."
  }

  assert {
    condition     = aws_iam_policy.console.name != aws_iam_policy.console_compute.name
    error_message = "The Console contract must be split across managed policies to remain below the AWS policy size limit."
  }

  assert {
    condition = alltrue([
      for action in [
        "eks:",
        "iam:CreatePolicy",
        "iam:CreateRole",
        "iam:DeletePolicy",
        "iam:DeleteRole",
      ] : !strcontains("${aws_iam_policy.console.policy}${aws_iam_policy.console_compute.policy}", action)
    ])
    error_message = "The EC2 minimal contract must not include EKS access or IAM role and policy lifecycle permissions from the default policy set."
  }

  assert {
    condition     = output.cluster_role_name == module.automq_role.role_name
    error_message = "The Cluster stage must receive the AWS role name expected by Console 8.3.16."
  }

  assert {
    condition     = length(aws_subnet.broker) == 3 && length(output.broker_networks) == 3
    error_message = "The quick path must create three private broker subnets across three zones."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.console_ui) == 1 && output.console_allowed_cidr_blocks[0] == "203.0.113.10/32"
    error_message = "The default Console ingress must be restricted to the detected caller IPv4 address."
  }

  assert {
    condition     = output.ops_bucket_name == "automq-ops-example" && aws_s3_bucket.ops.bucket == "automq-ops-example"
    error_message = "The ops bucket name from CONFIG must be created by the Console root."
  }

  assert {
    condition     = output.console_image == "automq.azurecr.io/automq/automq-byoc-console:8.3.16-aws"
    error_message = "The quick path must use the reviewed AutoMQ Console image by default."
  }

  assert {
    condition     = aws_instance.console.metadata_options[0].http_tokens == "required"
    error_message = "The Console EC2 instance must require IMDSv2 session tokens."
  }

  assert {
    condition     = !aws_subnet.console.map_public_ip_on_launch && aws_instance.console.associate_public_ip_address
    error_message = "Only the Console instance may explicitly request a public address; the public subnet must not assign one to every instance."
  }

  assert {
    condition = (
      strcontains(aws_instance.console.user_data, "retry 5 dnf install -y docker") &&
      strcontains(aws_instance.console.user_data, "retry 5 docker pull") &&
      strcontains(aws_instance.console.user_data, "--log-opt max-size=100m")
    )
    error_message = "Console bootstrap must retry downloads and bound container log growth."
  }

  assert {
    condition     = aws_instance.console.volume_tags["automqEnvironmentID"] == "env-example"
    error_message = "The Console root EBS volume must carry the environment ownership tags."
  }
}

run "explicit_console_allowlist_overrides_detection" {
  command = plan

  variables {
    console_allowed_cidr_blocks = ["198.51.100.20/32"]
  }

  assert {
    condition     = length(output.console_allowed_cidr_blocks) == 1 && output.console_allowed_cidr_blocks[0] == "198.51.100.20/32"
    error_message = "An explicit Console CIDR allowlist must override caller IP detection."
  }
}

run "empty_console_allowlist_is_rejected" {
  command = plan

  variables {
    console_allowed_cidr_blocks = []
  }

  expect_failures = [var.console_allowed_cidr_blocks]
}

run "vpc_without_subnet_capacity_is_rejected" {
  command = plan

  variables {
    vpc_cidr = "10.42.0.0/24"
  }

  expect_failures = [var.vpc_cidr]
}

run "ipv6_console_allowlist_is_rejected" {
  command = plan

  variables {
    console_allowed_cidr_blocks = ["2001:db8::/32"]
  }

  expect_failures = [var.console_allowed_cidr_blocks]
}

run "invalid_existing_data_bucket_name_is_rejected" {
  command = plan

  variables {
    data_bucket_name = "Invalid_Bucket_Name"
  }

  expect_failures = [var.data_bucket_name]
}

run "console_image_with_whitespace_is_rejected" {
  command = plan

  variables {
    console_image = "automq.azurecr.io/automq/automq-byoc-console:8.3.16-aws latest"
  }

  expect_failures = [var.console_image]
}

run "region_without_three_zones_is_rejected" {
  command = plan

  override_data {
    target = data.aws_availability_zones.available
    values = {
      names = ["us-east-1a", "us-east-1b"]
    }
  }

  expect_failures = [data.aws_availability_zones.available]
}

run "invalid_detected_caller_ip_is_rejected" {
  command = plan

  override_data {
    target = data.http.caller_ip[0]
    values = {
      response_body = "not-an-ip\n"
    }
  }

  expect_failures = [data.http.caller_ip[0]]
}
