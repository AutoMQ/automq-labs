# Terraform for AutoMQ on AWS EKS

This directory contains the Terraform configuration to provision the necessary AWS infrastructure for running an AutoMQ cluster on Amazon EKS (Elastic Kubernetes Service).

## Directory Structure

The Terraform code is organized into several modules for clarity and reusability:

-   `main.tf`: The root module that ties everything together. It defines the providers, local variables, and orchestrates the module calls.
-   `network/`: This module is responsible for creating the networking infrastructure, including the VPC, public and private subnets, and internet gateway.
-   `eks/`: This module sets up the EKS cluster itself, including the control plane.
-   `iam/`: This module creates the necessary IAM roles and policies required by the AutoMQ cluster running on the node group.

## Resources Created

This Terraform setup will create the following main resources in your AWS account:

-   **VPC**: A dedicated Virtual Private Cloud (VPC) to isolate the network resources.
-   **EKS Cluster**: A managed Kubernetes cluster control plane.
-   **EKS Node Group**: A group of EC2 instances that will serve as the worker nodes for the Kubernetes cluster. The instance type and scaling options can be configured in `main.tf`.
-   **S3 Buckets**: Creates S3 buckets for operational (ops) and application (data) storage.
-   **IAM Roles and Policies**: The necessary permissions for the EKS control plane and worker nodes to function correctly and access resources like S3.

## Usage

**Prerequisites**

-   **AWS CLI**: Ensure you have the AWS CLI installed and configured with appropriate credentials.


1.  **Initialize Terraform**:
    ```bash
    terraform init
    ```
2.  **Review the plan**:
    ```bash
    terraform plan
    ```
3.  **Apply the configuration**:
    ```bash
    terraform apply
    ```

After the apply is complete, Terraform will output the cluster name, VPC ID, and the AWS region.