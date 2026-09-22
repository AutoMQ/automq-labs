terraform {
  required_version = ">= 1.3"

  required_providers {
    automq = {
      source  = "automq/automq"
      version = "= 0.4.8"
    }
  }
}

# Read the endpoint and Service Account credentials from AUTOMQ_BYOC_* variables.
provider "automq" {}

resource "automq_kafka_instance" "demo" {
  environment_id = "<environment-id>"
  name           = "azure-managed-demo"
  description    = "Azure managed three zone demo"
  version        = "<supported-data-plane-version>"

  compute_specs = {
    deploy_type         = "K8S"
    pricing_mode        = "UsageBased"
    reserved_node_count = 3
    instance_types      = ["<supported-instance-type>"]

    kubernetes_cluster_id            = "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.ContainerService/managedClusters/<aks-name>"
    kubernetes_load_balancer_subnets = ["/subscriptions/<subscription-id>/resourceGroups/<network-resource-group>/providers/Microsoft.Network/virtualNetworks/<vnet-name>/subnets/<private-subnet-name>"]
    networks = [for zone in ["<zone-1>", "<zone-2>", "<zone-3>"] : {
      zone    = zone
      subnets = [] # AKS workload zones come from the node pool.
    }]

    schedule_spec = yamlencode({
      nodeSelector = {
        "kubernetes.azure.com/agentpool" = "<automq-node-pool-name>"
      }
      tolerations = [{
        key      = "dedicated"
        operator = "Equal"
        value    = "automq"
        effect   = "NoSchedule"
      }]
    })

    # Omit data_buckets, instance_role, and dns_zone for Control Plane management.
    # Do not supply the environment setup's customer-provided resource outputs.
    # The Control Plane also assigns the namespace and ServiceAccount.
  }

  features = {
    wal_mode = "S3WAL" # Object-storage WAL uses Azure Blob in this environment.
    security = {
      authentication_methods   = ["sasl"]
      transit_encryption_modes = ["plaintext"]
    }
  }
}

output "instance_id" {
  value = automq_kafka_instance.demo.id
}

output "endpoints" {
  value = automq_kafka_instance.demo.endpoints
}
