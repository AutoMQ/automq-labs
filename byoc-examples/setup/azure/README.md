# AutoMQ on Azure

This directory contains examples and tools to help you deploy AutoMQ on Microsoft Azure.

## Subdirectories

### [`arm/`](./arm/)

This directory contains an Azure Resource Manager (ARM) template to deploy the AutoMQ BYOC (Bring Your Own Cloud) Console. This is a quick way to get the console up and running.

See the [`arm/README.md`](./arm/README.md) for more details.

### [`azure-automq-env/`](./azure-automq-env/)

This is the main Terraform configuration for deploying a complete AutoMQ environment on Azure. It sets up an AKS cluster, a node pool for AutoMQ, the AutoMQ console, and all the necessary networking and IAM resources.

This is the recommended way to set up a production-ready AutoMQ environment on Azure.

See the [`azure-automq-env/README.md`](./azure-automq-env/README.md) for detailed instructions.

### [`network-example/`](./network-example/)

This directory contains a standalone Terraform example to create a Virtual Network (VNet) with public and private subnets, suitable for an AutoMQ deployment. This can be used as a prerequisite for setting up the `azure-automq-env`.

See the [`network-example/README.md`](./network-example/README.md) for more details.