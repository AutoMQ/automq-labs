output "cluster_autoscaler_role_arn" {
  description = "ARN of the Cluster Autoscaler IAM role"
  value       = var.enable_autoscaler ? module.cluster_autoscaler_irsa_role[0].arn : null
}

output "alb_controller_role_arn" {
  description = "ARN of the ALB Controller IAM role"
  value       = var.enable_alb_ingress_controller ? module.lb_irsa_role[0].arn : null
}

output "ebs_csi_role_arn" {
  description = "ARN of the EBS CSI IAM role"
  value       = var.enable_ebs_csi_driver ? module.ebs-csi-irsa-role[0].arn : null
}

output "cluster_autoscaler_helm_release_status" {
  description = "Status of the Cluster Autoscaler Helm release"
  value       = var.enable_autoscaler ? helm_release.autoscaler[0].status : "disabled"
}

output "alb_controller_helm_release_status" {
  description = "Status of the ALB Controller Helm release"
  value       = var.enable_alb_ingress_controller ? helm_release.alb_controller[0].status : "disabled"
}
