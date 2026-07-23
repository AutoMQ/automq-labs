# AutoMQ BYOC Console on GCP

This directory provides resources for deploying the AutoMQ BYOC Console in an
existing GCP VPC and subnet.

## Tools

- [Terraform](./terraform/): Provisions the Console VM, runtime identity, IAM,
  public endpoint, and persistent data disk.

To create a suitable GKE cluster and network first, use the
[GKE Terraform example](../kubernetes/gcp/terraform/).

After the GKE and Console setups are ready, the optional
[AutoMQ Instance example](./automq-cluster/) shows how to create a three-node,
usage-based S3WAL Instance with the `automq/automq` provider.
