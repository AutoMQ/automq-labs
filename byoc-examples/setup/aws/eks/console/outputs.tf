output "namespace" { value = kubernetes_namespace_v1.console.metadata[0].name }
output "service_name" { value = "automq-console-web-loadbalancer" }
output "port_forward_command" { value = "kubectl --namespace ${local.infra.console_namespace} port-forward --address 127.0.0.1 service/automq-console-web-loadbalancer 8080:80" }
