# AutoMQ on AWS

This section provides resources for deploying AutoMQ on Amazon Web Services.

## Setup Options

### [Kubernetes (EKS)](eks/README.md)

Create a new EKS cluster in an existing three-AZ network, deploy a released AutoMQ
Console with Helm, and create a managed Kafka Instance with a private endpoint.
The example reuses the shared [AWS Kubernetes modules](../kubernetes/aws/README.md).
Separate Pod roles provide AWS access, EKS Access Entry authorizes Console, and
Managed Node Groups with Cluster Autoscaler supply business-node capacity.

### [Amazon EC2](ec2/README.md)

Provision a self-contained AWS quick-start environment, run the AutoMQ BYOC
Console container on Amazon EC2, and create an AutoMQ data plane across three
Availability Zones.

* **Status:** Available
