---
last_updated: 2026-11-26
---

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

After the Kafka Instance is ready, the
[AutoMQ Connect example](./automq-connect/) creates a Connect Cluster on an
externally supplied GKE cluster and node pool, with the fixed Debezium MySQL
plugin and its Kubernetes and Google service accounts.
