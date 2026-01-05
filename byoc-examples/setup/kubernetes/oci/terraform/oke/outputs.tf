# kubeconfig
output "kubeconfig_command" {
  description = "Command for connecting OKE"
  value       = <<-EOT
    oci ce cluster create-kubeconfig \
      --cluster-id ${local.cluster_id} \
      --file $HOME/.kube/config \
      --region ${var.region} \
      --token-version 2.0.0 \
      --kube-endpoint PUBLIC_ENDPOINT
  EOT
}

output "automq_oke_storage_class_name" {
  description = "The name of the AutoMQ OKE Kubernetes Storage Class"
  value       = kubernetes_storage_class_v1.automq_oke_storage.metadata[0].name
}