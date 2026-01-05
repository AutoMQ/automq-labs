terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }

    kubernetes = {
      source = "hashicorp/kubernetes"
    }

    helm = {
      source = "hashicorp/helm"
    }

    kubectl = {
      source = "alekc/kubectl"
    }
  }
}