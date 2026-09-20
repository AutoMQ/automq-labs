mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "11111111-1111-1111-1111-111111111111"
    }
  }
}

mock_provider "local" {}

mock_provider "random" {
  mock_resource "random_string" {
    defaults = {
      result = "abc123"
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
      public_key_openssh = "ssh-rsa test"
      private_key_pem    = "test-private-key"
    }
  }
}

variables {
  automq_config = base64encode(jsonencode({
    environmentId = "env-example"
    clientId      = "client-id"
    clientSecret  = "client-secret"
    region        = "eastus"
    opsBucket = {
      bucketName = "amqopstest:ops"
    }
  }))
  console_image       = "automq.azurecr.io/automq/automq-byoc-console:8.3.0-azure"
  subscription_id     = "00000000-0000-0000-0000-000000000000"
  location            = "eastus"
  resource_group_name = "automq-test"
  env_prefix          = "automq"
  vnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-rg/providers/Microsoft.Network/virtualNetworks/automq"
  public_subnet_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-rg/providers/Microsoft.Network/virtualNetworks/automq/subnets/console"
  private_subnet_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-rg/providers/Microsoft.Network/virtualNetworks/automq/subnets/workload"
  service_cidr        = "172.2.0.0/16"
  dns_service_ip      = "172.2.0.10"
}

run "azure_8x_contract" {
  command = plan

  assert {
    condition     = output.storage_account_name == "amqopstest" && output.automq_ops_bucket == "ops"
    error_message = "The Ops Storage Account and Container must be decoded from CONFIG."
  }

  assert {
    condition     = output.ops_bucket_id == "amqopstest:ops"
    error_message = "The Console stack must create the canonical Azure Ops Bucket from CONFIG."
  }

}

run "config_region_must_match_location" {
  command = plan

  variables {
    location = "westus2"
  }

  expect_failures = [azurerm_resource_group.rg]
}

run "invalid_legacy_ops_bucket_is_rejected" {
  command = plan

  variables {
    automq_config = base64encode(jsonencode({
      environmentId = "env-example"
      clientId      = "client-id"
      clientSecret  = "client-secret"
      region        = "eastus"
      opsBucket = {
        bucketName = "legacy-container-only"
      }
    }))
  }

  expect_failures = [var.automq_config]
}

run "console_image_with_whitespace_is_rejected" {
  command = plan

  variables {
    console_image = "automq.azurecr.io/automq/automq-byoc-console:8.3.0-azure latest"
  }

  expect_failures = [var.console_image]
}
