output "cloud_provider" {
  description = "Cloud provider identifier"
  value       = "tencentcloud"
}

output "scope" {
  description = "Current account main UIN identifier"
  value       = data.tencentcloud_user_info.current.uin
}

output "region" {
  description = "Region"
  value       = var.region
}

output "zone" {
  description = "Primary availability zone"
  value       = local.azs[0]
}

output "cluster" {
  description = "ID of the TKE cluster"
  value       = tencentcloud_kubernetes_cluster.main.id
}

output "vpc_id" {
  description = "VPC ID"
  value       = tencentcloud_vpc.main.id
}

output "console_subnet_id" {
  description = "Public subnet ID for console placement"
  value       = tencentcloud_subnet.public.id
}

output "automq_subnet_map" {
  description = "Map of availability zones to private subnet IDs"
  value = {
    for zone, subnet_ids in {
      for subnet in tencentcloud_subnet.private :
      subnet.availability_zone => subnet.id...
    } : zone => subnet_ids
  }
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
  description = "K8s cluster auth info from TKE internet endpoint"
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
  description = "Kubeconfig"
  sensitive   = true
  value       = tencentcloud_kubernetes_cluster_endpoint.endpoint.kube_config
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
