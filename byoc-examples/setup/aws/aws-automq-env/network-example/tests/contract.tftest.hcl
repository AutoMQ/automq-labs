mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
}

variables {
  region             = "us-east-1"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

run "network_handoff" {
  command = plan
  assert {
    condition     = length(aws_subnet.private) == 3 && alltrue([for az, subnet in aws_subnet.private : subnet.availability_zone == az && !subnet.map_public_ip_on_launch])
    error_message = "The handoff must contain private subnets in three distinct AZs."
  }
  assert {
    condition     = aws_vpc_endpoint.s3.vpc_endpoint_type == "Gateway" && jsondecode(aws_vpc_endpoint.s3.policy).Statement[0].Resource == "*"
    error_message = "The S3 Gateway Endpoint must allow future managed bucket names; Pod IAM still grants object access."
  }
  assert {
    condition     = alltrue([for subnet in aws_subnet.public : !subnet.map_public_ip_on_launch])
    error_message = "Public subnets must not assign public IPs to arbitrary future nodes."
  }
}

run "duplicate_zones_are_rejected" {
  command = plan
  variables { availability_zones = ["us-east-1a", "us-east-1a", "us-east-1c"] }
  expect_failures = [var.availability_zones]
}

run "unavailable_zone_is_rejected" {
  command = plan
  variables { availability_zones = ["us-east-1a", "us-east-1b", "us-east-1z"] }
  expect_failures = [aws_vpc.this]
}
