
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"

    labels = {
      "app"        = "automq"
      "managed-by" = "terraform"
      "purpose"    = "monitoring"
    }

    annotations = {
      "description" = "Namespace for Monitoring"
    }
  }

  depends_on = [module.eks-env]
}

resource "helm_release" "prometheus" {
  chart      = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  name       = "prometheus"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  version    = "45.7.1"

  timeout = 600  # 不加会超时
  wait    = true

  create_namespace = true

  values = [
    templatefile("${path.module}/monitoring/prometheus.yaml")
  ]

  depends_on = [
    module.eks-env,
    kubernetes_namespace_v1.monitoring
  ]
}