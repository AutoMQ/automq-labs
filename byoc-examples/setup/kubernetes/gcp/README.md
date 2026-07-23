# Provisioning a Kubernetes Cluster on GCP

This directory provides resources for creating a GKE cluster and dedicated
AutoMQ workload node pool on Google Cloud.

## Tools

- [Terraform](./terraform/): Provisions the VPC, GKE cluster, and AutoMQ node
  pool.

To deploy the AutoMQ BYOC Console after the cluster is ready, use the
[GCP Console Terraform example](../../gcp/terraform/).
