terraform {
  required_version = ">= 1.3"

  required_providers {
    automq = {
      source  = "automq/automq"
      version = "~> 0.4.4"
    }
  }
}

locals {
  schedule_spec = trimspace(<<-YAML
    nodeSelector:
      node_type: automq
    tolerations:
      - key: dedicated
        operator: Equal
        value: automq
        effect: NoSchedule
  YAML
  )
}

provider "automq" {}

resource "automq_kafka_instance" "example" {
  environment_id = "<environment-id>"
  name           = "automq-gcp-example"
  description    = "Three-node S3WAL example on GKE"
  version        = "<supported-automq-version>"

  compute_specs = {
    pricing_mode        = "UsageBased"
    reserved_node_count = 3
    deploy_type         = "K8S"

    networks = [
      for zone in ["us-central1-a", "us-central1-b", "us-central1-c"] : {
        zone    = zone
        subnets = []
      }
    ]

    kubernetes_cluster_id            = "projects/<project-id>/locations/us-central1/clusters/automq-gke"
    instance_types                   = ["n4d-standard-2"]
    kubernetes_load_balancer_subnets = ["projects/<project-id>/regions/us-central1/subnetworks/automq-workload"]
    schedule_spec                    = local.schedule_spec
  }

  features = {
    wal_mode = "S3WAL"

    security = {
      authentication_methods   = ["anonymous"]
      transit_encryption_modes = ["plaintext"]
    }
  }
}

output "instance_id" {
  value = automq_kafka_instance.example.id
}

output "instance_status" {
  value = automq_kafka_instance.example.status
}

output "instance_endpoints" {
  value = automq_kafka_instance.example.endpoints
}
