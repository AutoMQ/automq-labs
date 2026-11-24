mock_provider "automq" {
  mock_resource "automq_connect_cluster" {
    defaults = {
      id    = "connect-cluster-example"
      state = "RUNNING"
    }
  }
}

mock_provider "http" {
  mock_data "http" {
    defaults = {
      status_code = 200
    }
  }
}

mock_provider "aws" {
  mock_data "aws_eks_cluster" {
    defaults = {
      arn      = "arn:aws:eks:us-east-1:123456789012:cluster/existing-eks-cluster"
      status   = "ACTIVE"
      endpoint = "https://eks.example.test"
      access_config = [{
        authentication_mode = "API_AND_CONFIG_MAP"
      }]
      certificate_authority = [{
        data = "dGVzdC1jYQ=="
      }]
      identity = [{
        oidc = [{
          issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
        }]
      }]
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_iam_openid_connect_provider" {
    defaults = {
      arn            = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
      client_id_list = ["sts.amazonaws.com"]
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      name = "mock-connect-worker"
      arn  = "arn:aws:iam::123456789012:role/mock-connect-worker"
    }
  }

  mock_resource "aws_eks_access_entry" {
    defaults = {
      access_entry_arn = "arn:aws:eks:us-east-1:123456789012:access-entry/existing-eks-cluster/role/123456789012/example-console/EXAMPLE"
    }
  }
}

mock_provider "kubernetes" {}

mock_provider "time" {}

override_data {
  target = data.terraform_remote_state.console
  values = {
    outputs = {
      environment_id             = "env-example"
      region                     = "us-east-1"
      ops_bucket_name            = "automq-ops-example"
      console_role_arn           = "arn:aws:iam::123456789012:role/example-console"
      console_endpoint           = "http://console.example:8080"
      console_initial_access_key = "example-access-key"
      console_initial_secret_key = "example-secret-key"
    }
  }
}

override_data {
  target = data.terraform_remote_state.kafka
  values = {
    outputs = {
      instance_id     = "kf-example"
      instance_status = "Running"
    }
  }
}

variables {
  kubernetes_cluster_id = "existing-eks-cluster"
  plugin_version        = "3.0.8.Final"
}

run "creates_connect_cluster_from_adjacent_states" {
  command = apply

  assert {
    condition = (
      local.console_state_valid &&
      local.kafka_state_valid &&
      output.environment_id == "env-example" &&
      output.kafka_instance_id == "kf-example" &&
      automq_connect_cluster.demo.environment_id == "env-example" &&
      automq_connect_cluster.demo.kafka_cluster.kafka_instance_id == "kf-example" &&
      output.connect_cluster_id == automq_connect_cluster.demo.id &&
      output.connect_cluster_state == "RUNNING"
    )
    error_message = "The Connect Cluster must reuse the environment and Kafka instance from the adjacent states and expose its lifecycle outputs."
  }

  assert {
    condition = (
      automq_connect_cluster.demo.name == "aws-mysql-connect-demo" &&
      automq_connect_cluster.demo.compute.type == "k8s" &&
      automq_connect_cluster.demo.compute.kubernetes.cluster_id == "existing-eks-cluster" &&
      automq_connect_cluster.demo.compute.kubernetes.namespace == kubernetes_namespace_v1.connect.metadata[0].name &&
      automq_connect_cluster.demo.compute.kubernetes.service_account == kubernetes_service_account_v1.connect.metadata[0].name &&
      automq_connect_cluster.demo.compute.iam_role == aws_iam_role.connect_worker.arn &&
      automq_connect_cluster.demo.capacity.type == "provisioned" &&
      automq_connect_cluster.demo.capacity.provisioned.worker_count == 1 &&
      automq_connect_cluster.demo.capacity.provisioned.worker_resource_spec == "TIER1"
    )
    error_message = "The default deployment must use one TIER1 worker on the external EKS cluster with its managed namespace, ServiceAccount, and Worker Role."
  }

  assert {
    condition = (
      length(automq_connect_cluster.demo.plugins) == 1 &&
      automq_connect_cluster.demo.plugins[0].name == "mysql-debezium-cdc" &&
      automq_connect_cluster.demo.plugins[0].version == "3.0.8.Final"
    )
    error_message = "The Connect Cluster must install the selected version of the existing MySQL Debezium plugin."
  }

  assert {
    condition = (
      kubernetes_namespace_v1.connect.metadata[0].name == "automq-connect" &&
      kubernetes_service_account_v1.connect.metadata[0].name == "automq-connect" &&
      kubernetes_service_account_v1.connect.metadata[0].namespace == kubernetes_namespace_v1.connect.metadata[0].name &&
      kubernetes_service_account_v1.connect.metadata[0].annotations["eks.amazonaws.com/role-arn"] == aws_iam_role.connect_worker.arn &&
      kubernetes_service_account_v1.connect.metadata[0].annotations["eks.amazonaws.com/sts-regional-endpoints"] == "true" &&
      kubernetes_service_account_v1.connect.automount_service_account_token &&
      length(aws_iam_role_policy_attachment.connect_worker) == 0 &&
      output.eks_cluster_name == data.aws_eks_cluster.target.name &&
      output.connect_namespace == kubernetes_namespace_v1.connect.metadata[0].name &&
      output.connect_service_account == kubernetes_service_account_v1.connect.metadata[0].name &&
      output.connect_iam_role_arn == aws_iam_role.connect_worker.arn
    )
    error_message = "The managed ServiceAccount must use the Worker Role through IRSA without attaching optional managed policies by default."
  }

  assert {
    condition = (
      length(jsondecode(aws_iam_role.connect_worker.assume_role_policy).Statement) == 1 &&
      jsondecode(aws_iam_role.connect_worker.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      jsondecode(aws_iam_role.connect_worker.assume_role_policy).Statement[0].Principal.Federated == data.aws_iam_openid_connect_provider.eks.arn &&
      length(keys(jsondecode(aws_iam_role.connect_worker.assume_role_policy).Statement[0].Condition.StringEquals)) == 2 &&
      jsondecode(aws_iam_role.connect_worker.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE:aud"] == "sts.amazonaws.com" &&
      jsondecode(aws_iam_role.connect_worker.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE:sub"] == "system:serviceaccount:automq-connect:automq-connect"
    )
    error_message = "IRSA trust must allow only the target cluster OIDC provider, STS audience, and exact managed namespace/ServiceAccount subject."
  }

  assert {
    condition = (
      aws_iam_role_policy.plugin_download.role == aws_iam_role.connect_worker.name &&
      length(jsondecode(aws_iam_role_policy.plugin_download.policy).Statement) == 2 &&
      alltrue([for statement in jsondecode(aws_iam_role_policy.plugin_download.policy).Statement : statement.Effect == "Allow"]) &&
      toset(flatten([for statement in jsondecode(aws_iam_role_policy.plugin_download.policy).Statement : statement.Action])) == toset(["s3:GetObject", "s3:ListBucket"]) &&
      one([for statement in jsondecode(aws_iam_role_policy.plugin_download.policy).Statement : statement if contains(statement.Action, "s3:GetObject")]).Resource == "arn:aws:s3:::automq-ops-example/automq/connect-plugins/*" &&
      one([for statement in jsondecode(aws_iam_role_policy.plugin_download.policy).Statement : statement if contains(statement.Action, "s3:ListBucket")]).Resource == "arn:aws:s3:::automq-ops-example" &&
      toset(one([for statement in jsondecode(aws_iam_role_policy.plugin_download.policy).Statement : statement if contains(statement.Action, "s3:ListBucket")]).Condition.StringLike["s3:prefix"]) == toset(["automq/connect-plugins", "automq/connect-plugins/*"])
    )
    error_message = "The default Worker Role must only read plugin objects and list the plugin prefix in its Console Ops Bucket."
  }

  assert {
    condition = (
      aws_iam_role_policy.console_eks.role == "example-console" &&
      aws_iam_role_policy.console_eks.role != aws_iam_role.connect_worker.name &&
      aws_eks_access_entry.console.cluster_name == data.aws_eks_cluster.target.name &&
      aws_eks_access_entry.console.principal_arn == "arn:aws:iam::123456789012:role/example-console" &&
      aws_eks_access_entry.console.principal_arn != aws_iam_role.connect_worker.arn &&
      aws_eks_access_entry.console.type == "STANDARD" &&
      aws_eks_access_policy_association.console.cluster_name == aws_eks_access_entry.console.cluster_name &&
      aws_eks_access_policy_association.console.principal_arn == aws_eks_access_entry.console.principal_arn &&
      aws_eks_access_policy_association.console.policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" &&
      aws_eks_access_policy_association.console.access_scope[0].type == "cluster" &&
      output.console_role_arn == aws_eks_access_entry.console.principal_arn &&
      output.console_eks_access_entry_arn == aws_eks_access_entry.console.access_entry_arn
    )
    error_message = "EKS API permissions and cluster-wide Kubernetes access must apply to the existing Console Role, separately from the Worker Role."
  }

  assert {
    condition = (
      time_sleep.console_eks_access.create_duration == "60s" &&
      time_sleep.console_eks_access.triggers["wait_duration"] == "60s"
    )
    error_message = "Console EKS authorization must have a default 60-second propagation buffer, with duration changes triggering a new wait."
  }

  assert {
    condition = (
      length(jsondecode(aws_iam_role_policy.console_eks.policy).Statement) == 5 &&
      alltrue([for statement in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : statement.Effect == "Allow"]) &&
      toset(flatten([for statement in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : statement.Action])) == toset([
        "eks:ListClusters",
        "eks:DescribeCluster",
        "eks:ListNodegroups",
        "eks:DescribeNodegroup",
        "eks:ListAccessEntries",
        "eks:DescribeAccessEntry",
        "eks:ListAssociatedAccessPolicies",
      ]) &&
      toset(one([for statement in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : statement if statement.Sid == "ListRegionalClusters"]).Action) == toset(["eks:ListClusters"]) &&
      one([for statement in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : statement if statement.Sid == "ListRegionalClusters"]).Resource == "*" &&
      one([for statement in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : statement if statement.Sid == "ListRegionalClusters"]).Condition.StringEquals["aws:RequestedRegion"] == "us-east-1" &&
      toset(one([for statement in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : statement if statement.Sid == "DescribeRegionalClusters"]).Action) == toset(["eks:DescribeCluster"]) &&
      one([for statement in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : statement if statement.Sid == "DescribeRegionalClusters"]).Resource == "arn:aws:eks:us-east-1:123456789012:cluster/*" &&
      toset(one([for statement in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : statement if statement.Sid == "InspectTargetCluster"]).Action) == toset(["eks:ListNodegroups", "eks:ListAccessEntries"]) &&
      one([for statement in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : statement if statement.Sid == "InspectTargetCluster"]).Resource == "arn:aws:eks:us-east-1:123456789012:cluster/existing-eks-cluster" &&
      toset(one([for statement in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : statement if statement.Sid == "DescribeTargetNodegroups"]).Action) == toset(["eks:DescribeNodegroup"]) &&
      one([for statement in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : statement if statement.Sid == "DescribeTargetNodegroups"]).Resource == "arn:aws:eks:us-east-1:123456789012:nodegroup/existing-eks-cluster/*/*" &&
      toset(one([for statement in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : statement if statement.Sid == "InspectTargetAccessEntries"]).Action) == toset(["eks:DescribeAccessEntry", "eks:ListAssociatedAccessPolicies"]) &&
      one([for statement in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : statement if statement.Sid == "InspectTargetAccessEntries"]).Resource == "arn:aws:eks:us-east-1:123456789012:access-entry/existing-eks-cluster/*"
    )
    error_message = "The Console IAM policy must grant only the seven required EKS read/list actions, with regional discovery and target-cluster inspection scopes."
  }
}

run "existing_eks_and_worker_settings_propagate" {
  command = apply

  variables {
    kubernetes_cluster_id      = "existing-production-eks"
    connect_namespace          = "existing-connect"
    connect_service_account    = "existing-connect-sa"
    kubernetes_scheduling_spec = "nodeSelector:\n  workload: connect\n"
    connect_worker_role_name   = "custom-connect-worker"
    connect_worker_policy_arns = [
      "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
      "arn:aws:iam::123456789012:policy/connect-worker-ops",
    ]
    connect_plugin_s3_prefix = "custom/connect-plugins"
    connect_cluster_name     = "custom-mysql-connect"
    connect_version          = "test-worker-version"
    worker_count             = 2
    worker_resource_spec     = "TIER2"
    plugin_name              = "custom-mysql-debezium-cdc"
    plugin_version           = "test-plugin-version"
  }

  override_data {
    target = data.aws_eks_cluster.target
    values = {
      arn      = "arn:aws:eks:us-east-1:123456789012:cluster/existing-production-eks"
      status   = "ACTIVE"
      endpoint = "https://eks.example.test"
      access_config = [{
        authentication_mode = "API_AND_CONFIG_MAP"
      }]
      certificate_authority = [{
        data = "dGVzdC1jYQ=="
      }]
      identity = [{
        oidc = [{
          issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
        }]
      }]
    }
  }

  assert {
    condition = (
      automq_connect_cluster.demo.name == "custom-mysql-connect" &&
      automq_connect_cluster.demo.version == "test-worker-version" &&
      automq_connect_cluster.demo.compute.kubernetes.cluster_id == "existing-production-eks" &&
      automq_connect_cluster.demo.compute.kubernetes.namespace == "existing-connect" &&
      automq_connect_cluster.demo.compute.kubernetes.service_account == "existing-connect-sa" &&
      yamldecode(automq_connect_cluster.demo.compute.kubernetes.scheduling_spec).nodeSelector.workload == "connect" &&
      aws_iam_role.connect_worker.name == "custom-connect-worker" &&
      automq_connect_cluster.demo.compute.iam_role == aws_iam_role.connect_worker.arn &&
      kubernetes_service_account_v1.connect.metadata[0].annotations["eks.amazonaws.com/role-arn"] == aws_iam_role.connect_worker.arn &&
      automq_connect_cluster.demo.capacity.provisioned.worker_count == 2 &&
      automq_connect_cluster.demo.capacity.provisioned.worker_resource_spec == "TIER2" &&
      automq_connect_cluster.demo.plugins[0].name == "custom-mysql-debezium-cdc" &&
      automq_connect_cluster.demo.plugins[0].version == "test-plugin-version"
    )
    error_message = "External EKS placement, the managed worker identity, runtime version, plugin selection, and provisioned capacity must reach the Connect resource."
  }

  assert {
    condition = (
      length(aws_iam_role_policy_attachment.connect_worker) == 2 &&
      aws_iam_role_policy_attachment.connect_worker["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"].role == aws_iam_role.connect_worker.name &&
      aws_iam_role_policy_attachment.connect_worker["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"].policy_arn == "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" &&
      aws_iam_role_policy_attachment.connect_worker["arn:aws:iam::123456789012:policy/connect-worker-ops"].role == aws_iam_role.connect_worker.name &&
      aws_iam_role_policy_attachment.connect_worker["arn:aws:iam::123456789012:policy/connect-worker-ops"].policy_arn == "arn:aws:iam::123456789012:policy/connect-worker-ops" &&
      kubernetes_service_account_v1.connect.metadata[0].namespace == "existing-connect" &&
      jsondecode(aws_iam_role.connect_worker.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE:sub"] == "system:serviceaccount:existing-connect:existing-connect-sa"
    )
    error_message = "Only explicitly supplied policies may attach to the Worker Role, whose trust must follow the configured namespace and ServiceAccount."
  }

  assert {
    condition = (
      one([for statement in jsondecode(aws_iam_role_policy.plugin_download.policy).Statement : statement if contains(statement.Action, "s3:GetObject")]).Resource == "arn:aws:s3:::automq-ops-example/custom/connect-plugins/*" &&
      one([for statement in jsondecode(aws_iam_role_policy.plugin_download.policy).Statement : statement if contains(statement.Action, "s3:ListBucket")]).Resource == "arn:aws:s3:::automq-ops-example" &&
      toset(one([for statement in jsondecode(aws_iam_role_policy.plugin_download.policy).Statement : statement if contains(statement.Action, "s3:ListBucket")]).Condition.StringLike["s3:prefix"]) == toset(["custom/connect-plugins", "custom/connect-plugins/*"])
    )
    error_message = "A customized plugin directory must update both object-read and bucket-list scopes without changing the Ops Bucket."
  }

  assert {
    condition = (
      aws_eks_access_entry.console.cluster_name == "existing-production-eks" &&
      aws_eks_access_policy_association.console.cluster_name == "existing-production-eks" &&
      aws_iam_role_policy.console_eks.role == "example-console" &&
      one([for statement in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : statement if statement.Sid == "InspectTargetCluster"]).Resource == "arn:aws:eks:us-east-1:123456789012:cluster/existing-production-eks" &&
      one([for statement in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : statement if statement.Sid == "DescribeTargetNodegroups"]).Resource == "arn:aws:eks:us-east-1:123456789012:nodegroup/existing-production-eks/*/*" &&
      one([for statement in jsondecode(aws_iam_role_policy.console_eks.policy).Statement : statement if statement.Sid == "InspectTargetAccessEntries"]).Resource == "arn:aws:eks:us-east-1:123456789012:access-entry/existing-production-eks/*"
    )
    error_message = "Changing the external EKS cluster must retarget Console access and all cluster-specific read scopes."
  }
}

run "console_endpoint_override_supports_an_open_ssm_tunnel" {
  command = plan

  variables {
    console_endpoint_override = "http://127.0.0.1:18080/"
  }

  assert {
    condition = (
      local.console_endpoint == "http://127.0.0.1:18080" &&
      data.http.console_login[0].url == "http://127.0.0.1:18080/auth/login" &&
      local.console_state_valid
    )
    error_message = "An endpoint override must direct the health check to the open tunnel while retaining Console state credentials."
  }
}

run "console_role_paths_are_not_passed_to_the_iam_policy_api" {
  command = apply

  override_data {
    target = data.terraform_remote_state.console
    values = {
      outputs = {
        environment_id             = "env-example"
        region                     = "us-east-1"
        ops_bucket_name            = "automq-ops-example"
        console_role_arn           = "arn:aws:iam::123456789012:role/team/path/example-console"
        console_endpoint           = "http://console.example:8080"
        console_initial_access_key = "example-access-key"
        console_initial_secret_key = "example-secret-key"
      }
    }
  }

  assert {
    condition = (
      aws_iam_role_policy.console_eks.role == "example-console" &&
      aws_eks_access_entry.console.principal_arn == "arn:aws:iam::123456789012:role/team/path/example-console" &&
      aws_eks_access_policy_association.console.principal_arn == aws_eks_access_entry.console.principal_arn &&
      output.console_role_arn == aws_eks_access_entry.console.principal_arn &&
      automq_connect_cluster.demo.compute.iam_role == aws_iam_role.connect_worker.arn &&
      automq_connect_cluster.demo.compute.iam_role != aws_eks_access_entry.console.principal_arn
    )
    error_message = "A Console Role with an IAM path must retain its complete access-entry ARN while the inline policy API receives only the role name."
  }
}

run "api_only_eks_authentication_is_supported" {
  command = plan

  override_data {
    target = data.aws_eks_cluster.target
    values = {
      arn      = "arn:aws:eks:us-east-1:123456789012:cluster/existing-eks-cluster"
      status   = "ACTIVE"
      endpoint = "https://eks.example.test"
      access_config = [{
        authentication_mode = "API"
      }]
      certificate_authority = [{
        data = "dGVzdC1jYQ=="
      }]
      identity = [{
        oidc = [{
          issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
        }]
      }]
    }
  }

  assert {
    condition     = data.aws_eks_cluster.target.access_config[0].authentication_mode == "API"
    error_message = "An external EKS cluster already using API-only authentication must pass preflight without changing its authentication mode."
  }
}

run "config_map_only_eks_authentication_is_rejected" {
  command = plan

  override_data {
    target = data.aws_eks_cluster.target
    values = {
      arn      = "arn:aws:eks:us-east-1:123456789012:cluster/existing-eks-cluster"
      status   = "ACTIVE"
      endpoint = "https://eks.example.test"
      access_config = [{
        authentication_mode = "CONFIG_MAP"
      }]
      certificate_authority = [{
        data = "dGVzdC1jYQ=="
      }]
      identity = [{
        oidc = [{
          issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
        }]
      }]
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "console_eks_access_wait_duration_is_configurable" {
  command = plan

  variables {
    console_eks_access_wait_duration = "2m"
  }

  assert {
    condition = (
      time_sleep.console_eks_access.create_duration == "2m" &&
      time_sleep.console_eks_access.triggers["wait_duration"] == "2m"
    )
    error_message = "A customized propagation buffer must reach both the wait duration and its replacement trigger."
  }
}

run "invalid_console_eks_access_wait_durations_are_rejected" {
  command = plan

  variables {
    console_eks_access_wait_duration = "forever"
  }

  expect_failures = [var.console_eks_access_wait_duration]
}

run "zero_workers_are_rejected" {
  command = plan

  variables {
    worker_count = 0
  }

  expect_failures = [var.worker_count]
}

run "fractional_workers_are_rejected" {
  command = plan

  variables {
    worker_count = 1.5
  }

  expect_failures = [var.worker_count]
}

run "unsupported_worker_tiers_are_rejected" {
  command = plan

  variables {
    worker_resource_spec = "TIER5"
  }

  expect_failures = [var.worker_resource_spec]
}

run "empty_eks_cluster_names_are_rejected" {
  command = plan

  variables {
    kubernetes_cluster_id = ""
  }

  expect_failures = [var.kubernetes_cluster_id]
}

run "eks_cluster_arns_are_rejected" {
  command = plan

  variables {
    kubernetes_cluster_id = "arn:aws:eks:us-east-1:123456789012:cluster/existing-eks"
  }

  expect_failures = [var.kubernetes_cluster_id]
}

run "malformed_console_state_is_rejected_before_creation" {
  command = plan

  override_data {
    target = data.terraform_remote_state.console
    values = {
      outputs = {
        environment_id             = "invalid-environment"
        region                     = "us-east-1"
        ops_bucket_name            = "automq-ops-example"
        console_role_arn           = "arn:aws:iam::123456789012:role/example-console"
        console_endpoint           = "http://console.example:8080"
        console_initial_access_key = "example-access-key"
        console_initial_secret_key = "example-secret-key"
      }
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "malformed_kafka_state_is_rejected_before_creation" {
  command = plan

  override_data {
    target = data.terraform_remote_state.kafka
    values = {
      outputs = {
        instance_id = "invalid-kafka-instance"
      }
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "unready_console_is_rejected_before_creation" {
  command = plan

  override_data {
    target = data.http.console_login[0]
    values = {
      status_code = 503
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "invalid_namespace_names_are_rejected" {
  command = plan

  variables {
    connect_namespace = "Invalid_Namespace"
  }

  expect_failures = [var.connect_namespace]
}

run "empty_service_account_names_are_rejected" {
  command = plan

  variables {
    connect_service_account = ""
  }

  expect_failures = [var.connect_service_account]
}

run "unfilled_plugin_versions_are_rejected" {
  command = plan

  variables {
    plugin_version = "REPLACE_WITH_AN_ACTIVE_PLUGIN_VERSION"
  }

  expect_failures = [var.plugin_version]
}

run "invalid_worker_role_names_are_rejected" {
  command = plan

  variables {
    connect_worker_role_name = "invalid worker role"
  }

  expect_failures = [var.connect_worker_role_name]
}

run "system_namespaces_cannot_be_managed" {
  command = plan

  variables {
    connect_namespace = "kube-system"
  }

  expect_failures = [var.connect_namespace]
}

run "default_service_accounts_cannot_be_managed" {
  command = plan

  variables {
    connect_service_account = "default"
  }

  expect_failures = [var.connect_service_account]
}

run "foreign_account_worker_policies_are_rejected" {
  command = plan

  variables {
    connect_worker_policy_arns = ["arn:aws:iam::999999999999:policy/foreign-worker-policy"]
  }

  expect_failures = [terraform_data.preflight]
}

run "foreign_partition_worker_policies_are_rejected" {
  command = plan

  variables {
    connect_worker_policy_arns = ["arn:aws-cn:iam::123456789012:policy/foreign-worker-policy"]
  }

  expect_failures = [terraform_data.preflight]
}

run "oidc_without_sts_audience_is_rejected" {
  command = plan

  override_data {
    target = data.aws_iam_openid_connect_provider.eks
    values = {
      arn            = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
      client_id_list = ["unexpected-audience.example"]
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "inactive_eks_clusters_are_rejected" {
  command = plan

  override_data {
    target = data.aws_eks_cluster.target
    values = {
      arn      = "arn:aws:eks:us-east-1:123456789012:cluster/existing-eks-cluster"
      status   = "CREATING"
      endpoint = "https://eks.example.test"
      access_config = [{
        authentication_mode = "API_AND_CONFIG_MAP"
      }]
      certificate_authority = [{
        data = "dGVzdC1jYQ=="
      }]
      identity = [{
        oidc = [{
          issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
        }]
      }]
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "eks_clusters_in_another_account_are_rejected" {
  command = plan

  override_data {
    target = data.aws_eks_cluster.target
    values = {
      arn      = "arn:aws:eks:us-east-1:999999999999:cluster/existing-eks-cluster"
      status   = "ACTIVE"
      endpoint = "https://eks.example.test"
      access_config = [{
        authentication_mode = "API_AND_CONFIG_MAP"
      }]
      certificate_authority = [{
        data = "dGVzdC1jYQ=="
      }]
      identity = [{
        oidc = [{
          issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
        }]
      }]
    }
  }

  expect_failures = [terraform_data.preflight]
}

run "aws_region_must_match_the_console_state" {
  command = plan

  variables {
    aws_region = "us-west-2"
  }

  expect_failures = [terraform_data.preflight]
}

run "wildcard_plugin_prefixes_are_rejected" {
  command = plan

  variables {
    connect_plugin_s3_prefix = "automq/connect-plugins/*"
  }

  expect_failures = [var.connect_plugin_s3_prefix]
}

run "console_roles_in_another_account_are_rejected" {
  command = plan

  override_data {
    target = data.terraform_remote_state.console
    values = {
      outputs = {
        environment_id             = "env-example"
        region                     = "us-east-1"
        ops_bucket_name            = "automq-ops-example"
        console_role_arn           = "arn:aws:iam::999999999999:role/foreign-console"
        console_endpoint           = "http://console.example:8080"
        console_initial_access_key = "example-access-key"
        console_initial_secret_key = "example-secret-key"
      }
    }
  }

  expect_failures = [terraform_data.preflight]
}
