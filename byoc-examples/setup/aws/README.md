---
last_updated: 2026-11-20
---

# AutoMQ on AWS

This section provides resources for deploying AutoMQ on Amazon Web Services.

## Setup Options

### [Interactive setup guide](interactive-setup/)

Start with an existing VPC. The guide discovers AWS resources and generates IAM
policies, optional Console installation commands, and a signed curl request to
create an AutoMQ cluster.

### [Kubernetes (EKS)](eks/README.md)

A comprehensive guide and Terraform scripts to set up a production-ready
AutoMQ cluster on Amazon Elastic Kubernetes Service (EKS).

* **Status:** Available

### [Amazon EC2](ec2/README.md)

Provision a self-contained AWS quick-start environment, run the AutoMQ BYOC
Console container on Amazon EC2, and create an AutoMQ data plane across three
Availability Zones.

* **Status:** Available
