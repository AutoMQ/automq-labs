# AutoMQ on AWS

This section provides resources for deploying AutoMQ on Amazon Web Services.

## Setup Options

### [New EKS with Helm Console (8.x)](aws-automq-env/README.md)

Create a new EKS cluster in an existing network, install Console with Pod ServiceAccount/RBAC and IRSA, and validate a managed private Kafka Instance. Requires a compatible Console image with the documented unreleased fixes. This is an independent evaluation path.

### [Kubernetes (EKS)](eks/README.md)

A comprehensive guide and Terraform scripts to set up a production-ready
AutoMQ cluster on Amazon Elastic Kubernetes Service (EKS).

* **Status:** Available

### [Amazon EC2](ec2/README.md)

Provision a self-contained AWS quick-start environment, run the AutoMQ BYOC
Console container on Amazon EC2, and create an AutoMQ data plane across three
Availability Zones.

* **Status:** Available
