mock_provider "aws" {}

variables {
  name_prefix      = "example-abcde"
  data_bucket_name = "automq-data-example"
  ops_bucket_name  = "automq-ops-example"
  hosted_zone_id   = "Z0123456789"
}

run "data_plane_policy_is_bucket_scoped" {
  command = plan

  assert {
    condition     = strcontains(output.policy_json, "arn:aws:s3:::automq-data-example")
    error_message = "The data-plane policy must include the configured data bucket."
  }

  assert {
    condition     = strcontains(output.policy_json, "arn:aws:s3:::automq-ops-example")
    error_message = "The data-plane policy must include the configured ops bucket."
  }

  assert {
    condition     = !strcontains(output.policy_json, "arn:aws:s3:::*")
    error_message = "The data-plane policy must not grant wildcard S3 bucket access."
  }

  assert {
    condition     = output.role_name == "automq-data-plane-example-abcde"
    error_message = "The data-plane role must use the expected deterministic name."
  }
}
