output "environment_id" {
  description = "AutoMQ environment read from the Console state"
  value       = local.environment_id
}

output "kafka_instance_id" {
  description = "Existing EC2 Kafka instance used by Connect"
  value       = local.kafka_instance_id
}

output "connect_cluster_id" {
  description = "AutoMQ Connect Cluster ID"
  value       = automq_connect_cluster.demo.id
}

output "connect_cluster_state" {
  description = "Connect Cluster lifecycle state reported by AutoMQ"
  value       = automq_connect_cluster.demo.state
}

output "eks_cluster_name" {
  description = "External EKS cluster used by Connect workers"
  value       = data.aws_eks_cluster.target.name
}

output "connect_namespace" {
  description = "Dedicated Kubernetes namespace managed by this example"
  value       = kubernetes_namespace_v1.connect.metadata[0].name
}

output "connect_service_account" {
  description = "Kubernetes ServiceAccount bound to the new Worker IAM Role"
  value       = kubernetes_service_account_v1.connect.metadata[0].name
}

output "connect_iam_role_arn" {
  description = "Worker IAM Role ARN passed to the Connect Cluster and annotated on its ServiceAccount"
  value       = aws_iam_role.connect_worker.arn
}

output "console_role_arn" {
  description = "Existing Console EC2 Role granted access to the external EKS cluster"
  value       = local.console_role_arn
}

output "console_eks_access_entry_arn" {
  description = "EKS Access Entry granting the existing Console Role cluster access"
  value       = aws_eks_access_entry.console.access_entry_arn
}
