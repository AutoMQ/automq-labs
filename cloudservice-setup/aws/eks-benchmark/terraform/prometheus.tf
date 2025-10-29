
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = var.prometheus_namespace

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
  version    = var.prometheus_chart_version

  timeout = 600 # 不加会超时
  wait    = true

  create_namespace = true

  values = [
    templatefile("${path.module}/monitoring/prometheus.yaml", {
      STORAGE_CLASS_NAME = var.prometheus_storage_class
    })
  ]

  depends_on = [
    module.eks-env,
    kubernetes_namespace_v1.monitoring,
    aws_eks_node_group.benchmark_node_group
  ]
}