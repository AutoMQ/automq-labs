output "cloud_provider" {
  description = "Cloud provider identifier"
  value       = "tencentcloud"
}

output "cloud_account_id" {
  description = "Tencent Cloud account ID (owner UIN)"
  value       = data.tencentcloud_user_info.current.owner_uin
}

output "region" {
  description = "Region"
  value       = var.region
}

output "zone" {
  description = "Primary availability zone (from the first provided subnet)"
  value       = data.tencentcloud_vpc_subnets.selected.instance_list[0].availability_zone
}

output "cluster" {
  description = "ID of the TKE cluster"
  value       = tencentcloud_kubernetes_cluster.main.id
}

output "vpc_id" {
  description = "VPC ID"
  value       = var.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs used for TKE cluster"
  value       = var.subnet_ids
}

output "ops_bucket_name" {
  description = "COS ops bucket name"
  value       = tencentcloud_cos_bucket.ops_bucket.bucket
}

output "cluster_security_group" {
  description = "TKE cluster security group ID"
  value       = tencentcloud_security_group.cluster_sg.id
}

# Outputs consumed by other modules
output "k8s_cluster_auth" {
  description = "K8s cluster auth info from TKE internet endpoint (empty when public access is disabled)"
  sensitive   = true
  value = {
    endpoint           = local.cluster_endpoint_internet
    ca_certificate     = local.cluster_ca_internet
    token              = ""
    client_key         = local.client_key_internet
    client_certificate = local.client_certificate_internet
  }
}

output "kube_config" {
  description = "Kubeconfig for internet endpoint (empty when public access is disabled)"
  sensitive   = true
  value       = var.enable_cluster_internet ? tencentcloud_kubernetes_cluster_endpoint.endpoint.kube_config : ""
}

output "k8s_cluster_auth_intranet" {
  description = "K8s cluster auth info from TKE intranet endpoint"
  sensitive   = true
  value = {
    endpoint           = local.cluster_endpoint_intranet
    ca_certificate     = local.cluster_ca_intranet
    token              = ""
    client_key         = local.client_key_intranet
    client_certificate = local.client_certificate_intranet
  }
}

output "kube_config_intranet" {
  description = "Kubeconfig"
  sensitive   = true
  value       = tencentcloud_kubernetes_cluster_endpoint.endpoint.kube_config_intranet
}
