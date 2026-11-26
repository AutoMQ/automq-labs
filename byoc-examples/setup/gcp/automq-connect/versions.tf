terraform {
  required_version = ">= 1.7.0, < 2.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    automq = {
      source  = "automq/automq"
      version = "= 0.4.10"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }
}

provider "google" {
  project = local.gke_project_id
  region  = local.console_region != "" ? local.console_region : "us-central1"
}

provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.target.endpoint}"
  cluster_ca_certificate = base64decode(data.google_container_cluster.target.master_auth[0].cluster_ca_certificate)

  # Use the same ADC identity as the Google provider and refresh short-lived tokens.
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
    args        = ["--use_application_default_credentials"]
  }
}

provider "automq" {
  automq_byoc_endpoint      = local.console_endpoint_valid ? local.console_endpoint : "http://127.0.0.1"
  automq_byoc_access_key_id = local.console_access_key_valid ? local.console_access_key : "missing-console-state"
  automq_byoc_secret_key    = local.console_secret_key_valid ? local.console_secret_key : "missing-console-state"
}
