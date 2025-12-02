
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

resource "kubernetes_config_map" "grafana-dashboard-config" {
  metadata {
    name      = "grafana-dashboard-config"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    labels = {
      grafana_dashboard = "1"
      prometheus        = "automq"
    }
  }
  data = {
    "cluster.json" = file("${path.module}/monitoring/dashboard/cluster.json")
    "broker.json"  = file("${path.module}/monitoring/dashboard/broker.json")
    "topics.json"  = file("${path.module}/monitoring/dashboard/topics.json")
    "group.json"   = file("${path.module}/monitoring/dashboard/group.json")
  }
  depends_on = [kubernetes_namespace_v1.monitoring]
}


resource "helm_release" "prometheus" {
  chart      = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  name       = "prometheus"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  version    = var.prometheus_chart_version

  timeout = 600
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
    aws_eks_node_group.benchmark_node_group,
    kubernetes_config_map.grafana-dashboard-config
  ]
}