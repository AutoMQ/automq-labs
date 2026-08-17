mock_provider "automq" {
  mock_resource "automq_kafka_instance" {
    defaults = {
      id     = "instance-example"
      status = "RUNNING"
    }
  }
}

variables {
  console_endpoint   = "http://console.example:8080"
  console_access_key = "access-key"
  console_secret_key = "secret-key"
  environment_id     = "env-example"

  private_subnet_ids_by_zone = {
    us-east-1c = ["subnet-c"]
    us-east-1a = ["subnet-a"]
    us-east-1b = ["subnet-b"]
  }

  data_bucket_name   = "automq-data-example"
  dns_zone_id        = "Z0123456789"
  instance_role_name = "automq-data-plane-example"
}

run "creates_bucket_scoped_iaas_instance" {
  command = apply

  assert {
    condition     = automq_kafka_instance.this.compute_specs.deploy_type == "IAAS"
    error_message = "The EC2 Custom example must always create an IAAS Instance."
  }

  assert {
    condition = (
      automq_kafka_instance.this.compute_specs.pricing_mode == "UsageBased" &&
      automq_kafka_instance.this.compute_specs.reserved_node_count == 3 &&
      automq_kafka_instance.this.compute_specs.instance_types[0] == "m7g.xlarge"
    )
    error_message = "The quick path must default to a three-node m7g.xlarge UsageBased Instance."
  }

  assert {
    condition     = automq_kafka_instance.this.compute_specs.instance_role == "automq-data-plane-example"
    error_message = "The IAAS Instance must use the dedicated data-plane Role name expected by Console 8.3.16."
  }

  assert {
    condition     = automq_kafka_instance.this.compute_specs.data_buckets[0].bucket_name == "automq-data-example" && automq_kafka_instance.this.compute_specs.dns_zone == "Z0123456789"
    error_message = "The IAAS Instance must use the Console stage data bucket and private DNS zone."
  }

  assert {
    condition     = output.broker_networks[0].zone == "us-east-1a" && output.broker_networks[2].zone == "us-east-1c"
    error_message = "The IAAS network payload must be sorted by availability zone."
  }

  assert {
    condition     = automq_kafka_instance.this.features.wal_mode == "EBSWAL"
    error_message = "The quick path must default to EBSWAL."
  }
}

run "role_arn_is_rejected" {
  command = plan

  variables {
    instance_role_name = "arn:aws:iam::123456789012:role/automq-data-plane-example"
  }

  expect_failures = [var.instance_role_name]
}

run "two_zone_topology_is_rejected" {
  command = plan

  variables {
    private_subnet_ids_by_zone = {
      us-east-1a = ["subnet-a"]
      us-east-1b = ["subnet-b"]
    }
  }

  expect_failures = [var.private_subnet_ids_by_zone]
}
