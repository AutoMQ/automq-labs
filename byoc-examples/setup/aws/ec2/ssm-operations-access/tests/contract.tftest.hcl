mock_provider "aws" {}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "123456789012" }
}

variables {
  region          = "us-east-1"
  automq_role_arn = "arn:aws:iam::210987654321:role/AutoMQOperator"
  external_id     = "customer-example"
  instance_ids    = ["i-0123456789abcdef0"]
}

run "operator_is_limited_to_approved_tagged_instances" {
  command = plan

  assert {
    condition = (
      jsondecode(nonsensitive(aws_iam_role.ssm_operator.assume_role_policy)).Statement[0].Principal.AWS == var.automq_role_arn &&
      jsondecode(nonsensitive(aws_iam_role.ssm_operator.assume_role_policy)).Statement[0].Condition.StringEquals["sts:ExternalId"] == "customer-example"
    )
    error_message = "The operator role must trust only the named AutoMQ role with the agreed External ID."
  }

  assert {
    condition = (
      one([for statement in jsondecode(aws_iam_role_policy.ssm_operator.policy).Statement : statement if statement.Sid == "StartSessionOnApprovedInstances"]).Resource == ["arn:aws:ec2:us-east-1:123456789012:instance/i-0123456789abcdef0"] &&
      one([for statement in jsondecode(aws_iam_role_policy.ssm_operator.policy).Statement : statement if statement.Sid == "StartSessionOnApprovedInstances"]).Condition.StringEquals["ssm:resourceTag/automqVendor"] == "automq" &&
      one([for statement in jsondecode(aws_iam_role_policy.ssm_operator.policy).Statement : statement if statement.Sid == "ProtectAccessTag"]).Effect == "Deny"
    )
    error_message = "The operator must reach only approved tagged instances and cannot change the access tag."
  }
}
