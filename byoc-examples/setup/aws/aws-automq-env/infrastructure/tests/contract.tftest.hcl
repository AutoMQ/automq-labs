mock_provider "aws" {
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_vpc" {
    defaults = {
      cidr_block              = "10.42.0.0/16"
      cidr_block_associations = [{ association_id = "vpc-cidr-assoc-1", cidr_block = "10.42.0.0/16", state = "associated" }]
      enable_dns_support      = true
      enable_dns_hostnames    = true
      owner_id                = "123456789012"
    }
  }
  mock_data "aws_route_table" {
    defaults = { id = "rtb-001", vpc_id = "vpc-001", routes = [{ cidr_block = "0.0.0.0/0", nat_gateway_id = "nat-existing" }] }
  }
  mock_data "aws_vpc_endpoint" {
    defaults = {
      vpc_id = "vpc-001", vpc_endpoint_type = "Gateway", service_name = "com.amazonaws.us-east-1.s3", route_table_ids = ["rtb-001"]
    }
  }
  mock_data "aws_ec2_instance_type" {
    defaults = { supported_architectures = ["x86_64", "arm64"], memory_size = 8192, default_vcpus = 2 }
  }
  mock_data "aws_eks_addon_version" { defaults = { version = "v1.2.3-eksbuild.1" } }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::automq-test-ops", id = "automq-test-ops" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock-role", id = "mock-role" }
  }
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-001", latest_version = 1 }
  }
  mock_resource "aws_eks_node_group" {
    defaults = { resources = [{ autoscaling_groups = [{ name = "mock-asg" }], remote_access_security_group_id = "" }] }
  }
  mock_resource "aws_eip" { defaults = { id = "eipalloc-0123456789abcdef0" } }
  mock_resource "aws_nat_gateway" { defaults = { id = "nat-0123456789abcdef0" } }
  mock_resource "aws_route" { defaults = { id = "mock-private-route" } }
  mock_data "aws_internet_gateway" {
    defaults = { id = "igw-001", attachments = [{ vpc_id = "vpc-001", state = "available" }] }
  }
}
mock_provider "tls" {}

override_resource {
  target = aws_iam_role.pod["console"]
  values = { id = "mock-console-role", arn = "arn:aws:iam::123456789012:role/mock-console-role" }
}

override_module {
  target = module.eks
  outputs = {
    cluster_name                       = "automq-eks-demo-eks"
    cluster_endpoint                   = "https://eks.example.test"
    cluster_certificate_authority_data = "dGVzdA=="
    cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
    oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
  }
}

override_data {
  target = data.aws_subnet.private["us-east-1a"]
  values = { id = "subnet-001", vpc_id = "vpc-001", availability_zone = "us-east-1a", map_public_ip_on_launch = false }
}
override_data {
  target = data.aws_subnet.private["us-east-1b"]
  values = { id = "subnet-002", vpc_id = "vpc-001", availability_zone = "us-east-1b", map_public_ip_on_launch = false }
}
override_data {
  target = data.aws_subnet.private["us-east-1c"]
  values = { id = "subnet-003", vpc_id = "vpc-001", availability_zone = "us-east-1c", map_public_ip_on_launch = false }
}

variables {
  automq_config = base64encode(jsonencode({
    environmentId = "env-example", clientId = "example-client", clientSecret = "example-only", region = "us-east-1", opsBucket = { bucketName = "automq-test-ops" }
  }))
  vpc_id                   = "vpc-001"
  private_subnet_ids_by_az = { us-east-1a = "subnet-001", us-east-1b = "subnet-002", us-east-1c = "subnet-003" }
  s3_vpc_endpoint_id       = "vpce-001"
  deployer_role_arn        = "arn:aws:iam::123456789012:role/deployer"
}

run "pod_identity_and_capacity_contract" {
  command = apply
  assert {
    condition = aws_iam_role_policy.console_discovery.role == aws_iam_role.pod["console"].id && aws_iam_role_policy.console_discovery.role != aws_iam_role.node.id && contains(
      jsondecode(aws_iam_role_policy.console_discovery.policy).Statement[0].Action, "ec2:DescribeInstanceTypeOfferings"
      ) && alltrue([
        for action in jsondecode(aws_iam_role_policy.console_discovery.policy).Statement[0].Action : can(regex("^[a-z0-9]+:(Describe|Get|List)[A-Za-z0-9]+$", action))
    ])
    error_message = "Instance-type offering discovery must be an exact read-only action on the Console Pod Role, never Node or a wildcard mutation grant."
  }
  assert {
    condition = toset([for attachment in aws_iam_role_policy_attachment.node : attachment.policy_arn]) == toset([
      "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy", "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
    ])
    error_message = "Node must have only worker/ECR foundation policies, never AutoMQ/CNI/CSI business access."
  }
  assert {
    condition = alltrue([for name, role in aws_iam_role.pod : (
      jsondecode(role.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE:aud"] == "sts.amazonaws.com" &&
      jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE:sub"] == local.pod_subjects[name]
    )])
    error_message = "Every Pod Role must bind both audience and its exact namespace/ServiceAccount."
  }
  assert {
    condition = length(aws_eks_node_group.automq) == 3 && alltrue([for az, group in aws_eks_node_group.automq :
      group.subnet_ids == toset([var.private_subnet_ids_by_az[az]]) && group.scaling_config[0].min_size == 1 && group.capacity_type == "ON_DEMAND" && group.ami_type == "AL2023_ARM_64_STANDARD"
    ])
    error_message = "Each AutoMQ AZ must have its own On-Demand ARM AL2023 capacity, not a shared desired count."
  }
  assert {
    condition = alltrue([for statement in jsondecode(aws_iam_role_policy.console_managed.policy).Statement :
      !contains(try(tolist(statement.Action), [statement.Action]), "ec2:RunInstances") && !contains(try(tolist(statement.Action), [statement.Action]), "iam:PassRole")
    ])
    error_message = "The K8S managed Console must not inherit EC2 deployment or PassRole privileges."
  }
  assert {
    condition     = one([for statement in jsondecode(aws_iam_role_policy.console_managed.policy).Statement : statement if statement.Sid == "ReconcileOwnedInstanceRoles"]).Condition.StringEquals["aws:ResourceTag/automqVendor"] == "automq"
    error_message = "Managed trust repair must be limited to owned Instance Roles."
  }
  assert {
    condition     = length(aws_autoscaling_group_tag.autoscaler) == 14
    error_message = "Autoscaler discovery and node-template tags must be installed on the underlying ASGs."
  }
}

run "service_cidr_overlap_is_rejected" {
  command = plan
  variables { service_ipv4_cidr = "10.42.0.0/16" }
  expect_failures = [terraform_data.network_contract]
}

run "missing_s3_route_association_is_rejected" {
  command = plan
  override_data {
    target = data.aws_vpc_endpoint.s3
    values = { vpc_id = "vpc-001", vpc_endpoint_type = "Gateway", service_name = "com.amazonaws.us-east-1.s3", route_table_ids = ["rtb-999"] }
  }
  expect_failures = [terraform_data.network_contract]
}

run "foreign_subnet_is_rejected" {
  command = plan
  override_data {
    target = data.aws_subnet.private["us-east-1a"]
    values = { id = "subnet-001", vpc_id = "vpc-999", availability_zone = "us-east-1a", map_public_ip_on_launch = false }
  }
  expect_failures = [terraform_data.network_contract]
}

run "duplicate_subnets_are_rejected" {
  command = plan
  variables { private_subnet_ids_by_az = { us-east-1a = "subnet-001", us-east-1b = "subnet-001", us-east-1c = "subnet-003" } }
  expect_failures = [var.private_subnet_ids_by_az]
}

run "public_api_cannot_default_to_internet" {
  command = plan
  variables { public_api_allowed_cidrs = ["0.0.0.0/0"] }
  expect_failures = [var.public_api_allowed_cidrs]
}

run "secondary_vpc_cidr_overlap_is_rejected" {
  command = plan
  override_data {
    target = data.aws_vpc.selected
    values = {
      cidr_block = "10.42.0.0/16"
      cidr_block_associations = [
        { association_id = "vpc-cidr-assoc-1", cidr_block = "10.42.0.0/16", state = "associated" },
        { association_id = "vpc-cidr-assoc-2", cidr_block = "172.20.0.0/16", state = "associated" },
      ]
      enable_dns_support = true, enable_dns_hostnames = true, owner_id = "123456789012"
    }
  }
  expect_failures = [terraform_data.network_contract]
}

run "wrong_az_mapping_is_rejected" {
  command = plan
  override_data {
    target = data.aws_subnet.private["us-east-1a"]
    values = { id = "subnet-001", vpc_id = "vpc-001", availability_zone = "us-east-1b", map_public_ip_on_launch = false }
  }
  expect_failures = [terraform_data.network_contract]
}

run "public_subnet_default_route_is_rejected" {
  command = plan
  override_data {
    target = data.aws_route_table.private["us-east-1a"]
    values = { id = "rtb-001", vpc_id = "vpc-001", routes = [{ cidr_block = "0.0.0.0/0", gateway_id = "igw-001" }] }
  }
  expect_failures = [terraform_data.network_contract]
}

run "malformed_config_is_rejected" {
  command = plan
  variables { automq_config = "invalid-base64" }
  expect_failures = [var.automq_config]
}

run "missing_egress_without_opt_in_is_rejected" {
  command = plan
  override_data {
    target = data.aws_route_table.private["us-east-1a"]
    values = { id = "rtb-001", vpc_id = "vpc-001", routes = [] }
  }
  expect_failures = [terraform_data.egress_contract]
}

run "nat_opt_in_creates_one_route_per_table" {
  command = apply
  variables {
    create_private_nat_egress = true
    nat_public_subnet_id      = "subnet-004"
  }
  override_data {
    target = data.aws_subnet.nat_public[0]
    values = { id = "subnet-004", vpc_id = "vpc-001", availability_zone = "us-east-1a" }
  }
  override_data {
    target = data.aws_route_table.nat_public[0]
    values = { id = "rtb-public", vpc_id = "vpc-001", routes = [{ cidr_block = "0.0.0.0/0", gateway_id = "igw-001" }] }
  }
  override_data {
    target = data.aws_route_table.private["us-east-1a"]
    values = { id = "rtb-001", vpc_id = "vpc-001", routes = [] }
  }
  override_data {
    target = data.aws_route_table.private["us-east-1b"]
    values = { id = "rtb-001", vpc_id = "vpc-001", routes = [] }
  }
  override_data {
    target = data.aws_route_table.private["us-east-1c"]
    values = { id = "rtb-001", vpc_id = "vpc-001", routes = [] }
  }
  assert {
    condition     = length(aws_route.private_nat) == 1 && aws_route.private_nat["rtb-001"].nat_gateway_id == aws_nat_gateway.private[0].id
    error_message = "Shared private route tables must get exactly one owned default route."
  }
}

run "second_plan_retains_owned_nat_route" {
  command = plan
  variables {
    create_private_nat_egress = true
    nat_public_subnet_id      = "subnet-004"
  }
  override_data {
    target = data.aws_subnet.nat_public[0]
    values = { id = "subnet-004", vpc_id = "vpc-001", availability_zone = "us-east-1a" }
  }
  override_data {
    target = data.aws_route_table.nat_public[0]
    values = { id = "rtb-public", vpc_id = "vpc-001", routes = [{ cidr_block = "0.0.0.0/0", gateway_id = "igw-001" }] }
  }
  override_data {
    target = data.aws_route_table.private["us-east-1a"]
    values = { id = "rtb-001", vpc_id = "vpc-001", routes = [{ cidr_block = "0.0.0.0/0", nat_gateway_id = "nat-0123456789abcdef0" }] }
  }
  override_data {
    target = data.aws_route_table.private["us-east-1b"]
    values = { id = "rtb-001", vpc_id = "vpc-001", routes = [{ cidr_block = "0.0.0.0/0", nat_gateway_id = "nat-0123456789abcdef0" }] }
  }
  override_data {
    target = data.aws_route_table.private["us-east-1c"]
    values = { id = "rtb-001", vpc_id = "vpc-001", routes = [{ cidr_block = "0.0.0.0/0", nat_gateway_id = "nat-0123456789abcdef0" }] }
  }
  assert {
    condition     = length(aws_route.private_nat) == 1 && aws_route.private_nat["rtb-001"].id == "mock-private-route" && aws_route.private_nat["rtb-001"].nat_gateway_id == "nat-0123456789abcdef0"
    error_message = "The second plan must retain the route identity, not add/delete it because the route is now visible."
  }
}

run "foreign_default_route_is_not_overwritten" {
  command = plan
  variables {
    create_private_nat_egress = true
    nat_public_subnet_id      = "subnet-004"
  }
  override_data {
    target = data.aws_subnet.nat_public[0]
    values = { id = "subnet-004", vpc_id = "vpc-001", availability_zone = "us-east-1a" }
  }
  override_data {
    target = data.aws_route_table.nat_public[0]
    values = { id = "rtb-public", vpc_id = "vpc-001", routes = [{ cidr_block = "0.0.0.0/0", gateway_id = "igw-001" }] }
  }
  expect_failures = [terraform_data.egress_contract]
}

run "environment_id_empty_is_rejected" {
  command = plan
  variables {
    automq_config = base64encode(jsonencode({ "environmentId" = "", "clientId" = "example-client", "clientSecret" = "example-only", "region" = "us-east-1", "opsBucket" = { "bucketName" = "automq-test-ops" } }))
  }
  expect_failures = [var.automq_config]
}

run "environment_id_whitespace_is_rejected" {
  command = plan
  variables {
    automq_config = base64encode(jsonencode({ "environmentId" = " \t\n ", "clientId" = "example-client", "clientSecret" = "example-only", "region" = "us-east-1", "opsBucket" = { "bucketName" = "automq-test-ops" } }))
  }
  expect_failures = [var.automq_config]
}

run "environment_id_missing_is_rejected" {
  command = plan
  variables {
    automq_config = base64encode(jsonencode({ "clientId" = "example-client", "clientSecret" = "example-only", "region" = "us-east-1", "opsBucket" = { "bucketName" = "automq-test-ops" } }))
  }
  expect_failures = [var.automq_config]
}

run "client_id_empty_is_rejected" {
  command = plan
  variables {
    automq_config = base64encode(jsonencode({ "environmentId" = "env-example", "clientId" = "", "clientSecret" = "example-only", "region" = "us-east-1", "opsBucket" = { "bucketName" = "automq-test-ops" } }))
  }
  expect_failures = [var.automq_config]
}

run "client_id_whitespace_is_rejected" {
  command = plan
  variables {
    automq_config = base64encode(jsonencode({ "environmentId" = "env-example", "clientId" = " \t\n ", "clientSecret" = "example-only", "region" = "us-east-1", "opsBucket" = { "bucketName" = "automq-test-ops" } }))
  }
  expect_failures = [var.automq_config]
}

run "client_id_missing_is_rejected" {
  command = plan
  variables {
    automq_config = base64encode(jsonencode({ "environmentId" = "env-example", "clientSecret" = "example-only", "region" = "us-east-1", "opsBucket" = { "bucketName" = "automq-test-ops" } }))
  }
  expect_failures = [var.automq_config]
}

run "client_secret_empty_is_rejected" {
  command = plan
  variables {
    automq_config = base64encode(jsonencode({ "environmentId" = "env-example", "clientId" = "example-client", "clientSecret" = "", "region" = "us-east-1", "opsBucket" = { "bucketName" = "automq-test-ops" } }))
  }
  expect_failures = [var.automq_config]
}

run "client_secret_whitespace_is_rejected" {
  command = plan
  variables {
    automq_config = base64encode(jsonencode({ "environmentId" = "env-example", "clientId" = "example-client", "clientSecret" = " \t\n ", "region" = "us-east-1", "opsBucket" = { "bucketName" = "automq-test-ops" } }))
  }
  expect_failures = [var.automq_config]
}

run "client_secret_missing_is_rejected" {
  command = plan
  variables {
    automq_config = base64encode(jsonencode({ "environmentId" = "env-example", "clientId" = "example-client", "region" = "us-east-1", "opsBucket" = { "bucketName" = "automq-test-ops" } }))
  }
  expect_failures = [var.automq_config]
}

run "region_empty_is_rejected" {
  command = plan
  variables {
    automq_config = base64encode(jsonencode({ "environmentId" = "env-example", "clientId" = "example-client", "clientSecret" = "example-only", "region" = "", "opsBucket" = { "bucketName" = "automq-test-ops" } }))
  }
  expect_failures = [var.automq_config]
}

run "region_whitespace_is_rejected" {
  command = plan
  variables {
    automq_config = base64encode(jsonencode({ "environmentId" = "env-example", "clientId" = "example-client", "clientSecret" = "example-only", "region" = " \t\n ", "opsBucket" = { "bucketName" = "automq-test-ops" } }))
  }
  expect_failures = [var.automq_config]
}

run "region_missing_is_rejected" {
  command = plan
  variables {
    automq_config = base64encode(jsonencode({ "environmentId" = "env-example", "clientId" = "example-client", "clientSecret" = "example-only", "opsBucket" = { "bucketName" = "automq-test-ops" } }))
  }
  expect_failures = [var.automq_config]
}

run "ops_bucket_name_empty_is_rejected" {
  command = plan
  variables {
    automq_config = base64encode(jsonencode({ "environmentId" = "env-example", "clientId" = "example-client", "clientSecret" = "example-only", "region" = "us-east-1", "opsBucket" = { "bucketName" = "" } }))
  }
  expect_failures = [var.automq_config]
}

run "ops_bucket_name_whitespace_is_rejected" {
  command = plan
  variables {
    automq_config = base64encode(jsonencode({ "environmentId" = "env-example", "clientId" = "example-client", "clientSecret" = "example-only", "region" = "us-east-1", "opsBucket" = { "bucketName" = " \t\n " } }))
  }
  expect_failures = [var.automq_config]
}

run "ops_bucket_name_missing_is_rejected" {
  command = plan
  variables {
    automq_config = base64encode(jsonencode({ "environmentId" = "env-example", "clientId" = "example-client", "clientSecret" = "example-only", "region" = "us-east-1", "opsBucket" = {} }))
  }
  expect_failures = [var.automq_config]
}

run "invalid_json_config_is_rejected" {
  command = plan
  variables { automq_config = base64encode("{broken-json") }
  expect_failures = [var.automq_config]
}
