mock_provider "aws" {
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/automq-test"
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
    condition     = strcontains(aws_iam_policy.console.policy, module.automq_role.role_arn)
    error_message = "The Console PassRole permission must reference the dedicated data-plane role."
  }

  assert {
    condition = alltrue([
      for action in [
        "iam:GetPolicy",
        "iam:GetRole",
        "iam:GetRolePolicy",
        "iam:GetPolicyVersion",
        "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfilesForRole",
        "iam:ListRolePolicies",
        "s3:GetBucketLocation",
        "s3:GetBucketTagging",
        "s3:GetLifecycleConfiguration",
        "s3:ListBucket",
      ] : strcontains(aws_iam_policy.console.policy, action)
    ])
    error_message = "The Console must be able to validate the Terraform-managed data bucket and data-plane role before instance creation."
  }

  assert {
    condition     = output.cluster_role_name == module.automq_role.role_name
    error_message = "The Cluster stage must receive the AWS role name expected by Console 8.3.16."
  }

  assert {
    condition     = length(aws_subnet.broker) == 3 && length(output.private_subnet_ids_by_zone) == 3
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
