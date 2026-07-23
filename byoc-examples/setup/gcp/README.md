# AutoMQ BYOC Console on GCP

This directory provides resources for deploying the AutoMQ BYOC Console in an
existing GCP VPC and subnet.

## Tools

- [Terraform](./terraform/): Provisions the Console VM, runtime identity, IAM,
  public endpoint, and persistent data disk.

To create a suitable GKE cluster and network first, use the
[GKE Terraform example](../kubernetes/gcp/terraform/).
