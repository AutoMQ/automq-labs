mock_provider "aws" {
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
  mock_data "aws_eks_cluster" {
    defaults = {
      endpoint              = "https://eks.example.test"
      certificate_authority = [{ data = "dGVzdA==" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE" }] }]
      vpc_config            = [{ cluster_security_group_id = "sg-example", subnet_ids = ["subnet-a", "subnet-b"], vpc_id = "vpc-example" }]
    }
  }
  mock_data "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE" }
  }
  mock_data "aws_eks_addon_version" { defaults = { version = "v1.2.3-eksbuild.1" } }
  mock_resource "aws_iam_role" { defaults = { arn = "arn:aws:iam::123456789012:role/mock-component", id = "mock-component" } }
  mock_resource "aws_launch_template" { defaults = { id = "lt-example", latest_version = 1 } }
  mock_resource "aws_eks_node_group" {
    defaults = { resources = [{ autoscaling_groups = [{ name = "example-asg" }], remote_access_security_group_id = "" }] }
  }
}
mock_provider "random" {
  mock_resource "random_string" { defaults = { result = "abcde" } }
}
mock_provider "null" {}
mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "tls" {}
mock_provider "time" {}
mock_provider "cloudinit" {}

override_module {
  target = module.eks
  outputs = {
    cluster_name                       = "fixture-eks"
    cluster_endpoint                   = "https://eks.example.test"
    cluster_certificate_authority_data = "dGVzdA=="
    cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
    oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
    cluster_primary_security_group_id  = "sg-cluster"
  }
}

override_resource {
  target          = random_string.suffix
  override_during = plan
  values          = { id = "abcde", result = "abcde" }
}

variables {
  region          = "us-east-1"
  resource_suffix = "fixture"
  vpc_id          = "vpc-example"
  subnet_ids      = ["subnet-a", "subnet-b", "subnet-c"]
  cluster_name    = "fixture-eks"
}

run "existing_call_preserves_system_nodes_and_outputs" {
  command = plan

  override_module {
    target = module.eks_addons[0]
    outputs = {
      cluster_autoscaler_role_arn            = "arn:aws:iam::123456789012:role/legacy-ca"
      alb_controller_role_arn                = "arn:aws:iam::123456789012:role/legacy-lb"
      ebs_csi_role_arn                       = "arn:aws:iam::123456789012:role/legacy-csi"
      cluster_autoscaler_helm_release_status = "deployed"
      alb_controller_helm_release_status     = "deployed"
    }
  }
  assert {
    condition = (
      aws_eks_node_group.system_nodes.node_group_name == "system-nodes" &&
      aws_eks_node_group.system_nodes.capacity_type == "SPOT" &&
      aws_eks_node_group.system_nodes.instance_types == tolist(["t3.medium", "c5.large", "t3.small"]) &&
      aws_eks_node_group.system_nodes.scaling_config[0].min_size == 3 &&
      aws_eks_node_group.system_nodes.scaling_config[0].desired_size == 4 &&
      aws_eks_node_group.system_nodes.scaling_config[0].max_size == 6
    )
    error_message = "Existing callers must retain the original system group name, Spot instance choices and 3/4/6 capacity."
  }
  assert {
    condition = (
      length(aws_eks_node_group.workload) == 0 && length(aws_launch_template.nodes) == 0 &&
      length(aws_iam_role.pod) == 0 && length(aws_autoscaling_group_tag.autoscaler) == 0 &&
      length(aws_eks_addon.vpc_cni) == 0 && length(aws_eks_addon.after_nodes) == 0 &&
      length(aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy) == 1
    )
    error_message = "New pools, Pod roles and AWS-stage addons must be opt-in; the existing Node CNI policy must remain."
  }
  assert {
    condition = (
      aws_iam_role.node_group_role.name == "abcde-fixture-node-group-role" &&
      aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly.policy_arn == "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly" &&
      output.eks_cluster_name == "fixture-eks" && output.eks_cluster_security_group == "sg-cluster" &&
      output.eks_cluster_endpoint == "https://eks.example.test" && output.eks_cluster_ca_certificate == "dGVzdA==" &&
      output.cluster_autoscaler_role_arn == "arn:aws:iam::123456789012:role/legacy-ca" &&
      output.alb_controller_helm_release_status == "deployed"
    )
    error_message = "The old role naming, policies and outputs used by Playground must stay compatible."
  }
}

run "default_cluster_name_keeps_random_suffix" {
  command = plan
  variables { cluster_name = "" }
  override_resource {
    target          = random_string.suffix
    override_during = plan
    values          = { id = "abcde", result = "abcde" }
  }
  override_module {
    target = module.eks_addons[0]
    outputs = {
      cluster_autoscaler_role_arn            = "arn:aws:iam::123456789012:role/legacy-ca"
      alb_controller_role_arn                = "arn:aws:iam::123456789012:role/legacy-lb"
      ebs_csi_role_arn                       = "arn:aws:iam::123456789012:role/legacy-csi"
      cluster_autoscaler_helm_release_status = "deployed"
      alb_controller_helm_release_status     = "deployed"
    }
  }
  assert {
    condition     = output.eks_cluster_name == "eks-abcde-fixture"
    error_message = "Callers omitting cluster_name must retain the existing random-prefix naming convention."
  }
}

run "three_az_pod_identity_capacity" {
  command = apply
  variables {
    cluster_options = {
      kubernetes_version                       = "1.36"
      endpoint_public_access                   = false
      authentication_mode                      = "API"
      enable_cluster_creator_admin_permissions = false
      deployer_role_arn                        = "arn:aws:iam::123456789012:role/deployer"
      log_retention_days                       = 7
    }
    system_node_group = {
      name     = "fixture-system", instance_types = ["m7i.large"], capacity_type = "ON_DEMAND"
      ami_type = "AL2023_x86_64_STANDARD", kubernetes_version = "1.36"
      min_size = 2, desired_size = 2, max_size = 4
      labels   = { "automq.io/pool" = "system" }, launch_template_key = "system", max_unavailable = 1
    }
    workload_node_groups = {
      us-east-1a = { name = "fixture-automq-us-east-1a", subnet_ids = ["subnet-a"], instance_types = ["m7g.xlarge"], ami_type = "AL2023_ARM_64_STANDARD", kubernetes_version = "1.36", min_size = 1, desired_size = 1, max_size = 4, labels = { "automq.io/pool" = "automq" }, taints = [{ key = "dedicated", value = "automq", effect = "NO_SCHEDULE" }], launch_template_key = "automq" }
      us-east-1b = { name = "fixture-automq-us-east-1b", subnet_ids = ["subnet-b"], instance_types = ["m7g.xlarge"], ami_type = "AL2023_ARM_64_STANDARD", kubernetes_version = "1.36", min_size = 1, desired_size = 1, max_size = 4, labels = { "automq.io/pool" = "automq" }, taints = [{ key = "dedicated", value = "automq", effect = "NO_SCHEDULE" }], launch_template_key = "automq" }
      us-east-1c = { name = "fixture-automq-us-east-1c", subnet_ids = ["subnet-c"], instance_types = ["m7g.xlarge"], ami_type = "AL2023_ARM_64_STANDARD", kubernetes_version = "1.36", min_size = 1, desired_size = 1, max_size = 4, labels = { "automq.io/pool" = "automq" }, taints = [{ key = "dedicated", value = "automq", effect = "NO_SCHEDULE" }], launch_template_key = "automq" }
    }
    node_iam                    = { role_name = "fixture-node", attach_cni_policy = false, ecr_policy_name = "AmazonEC2ContainerRegistryPullOnly" }
    node_launch_templates       = { system = { name_prefix = "fixture-system-" }, automq = { name_prefix = "fixture-automq-" } }
    component_irsa_prefix       = "fixture"
    manage_core_addons          = true
    install_addons              = false
    manage_kubeconfig           = false
    enable_autoscaler_discovery = true
  }
  assert {
    condition = (
      length(aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy) == 0 &&
      aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy.policy_arn == "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy" &&
      aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly.policy_arn == "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly" &&
      aws_iam_role.node_group_role.name == "fixture-node"
    )
    error_message = "Explicit Pod identity mode must leave Nodes with only Worker/ECR foundation policies."
  }
  assert {
    condition = length(aws_eks_node_group.workload) == 3 && alltrue([for az, pool in aws_eks_node_group.workload :
      pool.subnet_ids == toset(var.workload_node_groups[az].subnet_ids) && length(pool.subnet_ids) == 1 &&
      pool.capacity_type == "ON_DEMAND" && pool.ami_type == "AL2023_ARM_64_STANDARD" &&
      pool.scaling_config[0].min_size == 1 && pool.scaling_config[0].max_size == 4 &&
      one(pool.taint).key == "dedicated" && one(pool.taint).effect == "NO_SCHEDULE"
    ])
    error_message = "Each of three AZs needs its own private ARM AL2023 node group and workload isolation."
  }
  assert {
    condition = length(aws_iam_role.pod) == 4 && alltrue([for name, role in aws_iam_role.pod :
      jsondecode(role.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE:aud"] == "sts.amazonaws.com" &&
      jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE:sub"] == local.component_subjects[name]
    ])
    error_message = "Every component role must bind its own exact ServiceAccount and sts audience."
  }
  assert {
    condition = alltrue([for template in aws_launch_template.nodes :
      template.metadata_options[0].http_tokens == "required" && template.metadata_options[0].http_put_response_hop_limit == 1 &&
      one(template.block_device_mappings).ebs[0].volume_size == 40 && one(template.block_device_mappings).ebs[0].encrypted && one(template.block_device_mappings).ebs[0].delete_on_termination
    ])
    error_message = "Explicit launch templates must require IMDSv2, hop limit one and encrypted disposable gp3 roots."
  }
  assert {
    condition = (
      length(aws_autoscaling_group_tag.autoscaler) == 14 &&
      aws_autoscaling_group_tag.autoscaler["us-east-1a:k8s.io/cluster-autoscaler/node-template/taint/dedicated"].tag[0].value == "automq:NoSchedule" &&
      length(module.eks_addons) == 0 && length(null_resource.kube_config) == 0 &&
      aws_eks_addon.vpc_cni[0].service_account_role_arn == aws_iam_role.pod["cni"].arn &&
      aws_eks_addon.after_nodes["aws-ebs-csi-driver"].service_account_role_arn == aws_iam_role.pod["ebs-csi"].arn
    )
    error_message = "Discovery tags must reach all four ASGs, and AWS-stage CNI/CSI must use their own IRSA roles without embedded Helm installation."
  }
}

run "core_addons_with_embedded_helm_keep_existing_role_outputs" {
  command = apply
  variables {
    component_irsa_prefix = "fixture"
    manage_core_addons    = true
    install_addons        = true
    manage_kubeconfig     = false
    node_iam              = { attach_cni_policy = false }
  }
  override_module {
    target  = module.eks_addons[0].module.cluster_exteranl_dns_irsa_role[0]
    outputs = { arn = "arn:aws:iam::123456789012:role/legacy-dns" }
  }
  assert {
    condition = (
      module.eks_addons[0].ebs_csi_role_arn == null &&
      output.ebs_csi_role_arn == aws_iam_role.pod["ebs-csi"].arn &&
      output.cluster_autoscaler_role_arn == aws_iam_role.pod["autoscaler"].arn &&
      output.alb_controller_role_arn == aws_iam_role.pod["lb-controller"].arn &&
      output.ebs_csi_role_arn != null && output.cluster_autoscaler_role_arn != null && output.alb_controller_role_arn != null
    )
    error_message = "Core-owned component roles must remain available through the existing outputs when managed core addons and embedded Helm installation are both enabled."
  }
}
