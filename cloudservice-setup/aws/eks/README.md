# AutoMQ BYOC on Amazon EKS

This document provides instructions for deploying an AutoMQ BYOC (Bring Your Own Cloud) environment on Amazon EKS (Elastic Kubernetes Service) using Terraform.

This project automates the setup process detailed in the [official AutoMQ documentation](https://www.automq.com/docs/automq-cloud/deploy-automq-on-kubernetes/deploy-to-aws-eks), providing a repeatable and efficient way to provision a Poc environment.

## Architecture

This Terraform project provisions and configures the following core AWS and Kubernetes resources:

1.  **Amazon EKS Cluster**: A new EKS cluster is created, including the necessary VPC, subnets, and foundational security groups.
2.  **AutoMQ BYOC Environment**: The official `AutoMQ/automq-byoc-environment/aws` module is used to deploy the AutoMQ Console, which is the central management plane for your message queues.
3.  **EKS Node Group**: A dedicated EKS node group is configured for running AutoMQ workloads, with appropriate instance types and taints (`dedicated=automq:NoSchedule`) to ensure workloads are isolated.
4.  **Essential EKS Add-ons**: The setup automatically configures critical add-ons required for a fully functional cluster:
    *   **AWS Load Balancer Controller**: Manages AWS Load Balancers for services of type `LoadBalancer`.
    *   **Amazon EBS CSI Driver**: Allows Kubernetes to manage persistent storage using Amazon EBS volumes.
    *   **Cluster Autoscaler**: Automatically adjusts the number of nodes in your EKS cluster based on workload demands.
5.  **IAM Roles & Permissions**: All necessary IAM roles and policies are created and associated, including:
    *   An EKS Cluster Role.
    *   An EKS Node Group Role with policies for ECR, CNI, and worker node operations.
    *   IAM Roles for Service Accounts (IRSA) for the EBS CSI Driver, Load Balancer Controller, and Cluster Autoscaler.
6.  **Integration and Authorization**:
    *   Security group rules are configured to allow secure communication between the AutoMQ Console and the EKS cluster.
    *   An EKS Access Entry is created to grant the AutoMQ Console's IAM role administrative privileges over the cluster, enabling it to deploy and manage AutoMQ.

## Prerequisites

Before you begin, ensure you have the following tools installed and configured:

*   [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli) (v1.0.0+)
*   [AWS CLI](https://aws.amazon.com/cli/)
*   [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
*   Configured AWS credentials with permissions to create the resources defined in this project.

## Usage

1.  **Initialize Terraform**
    In the `terraform` directory, run `terraform init` to initialize the workspace and download the required modules.
    ```bash
    cd terraform
    terraform init
    ```

2.  **Plan the Deployment**
    Run `terraform plan` to preview the resources that will be created.
    ```bash
    terraform plan
    ```

3.  **Apply the Deployment**
    After reviewing the plan, execute `terraform apply` to begin the deployment. This process may take 15-20 minutes.
    ```bash
    terraform apply
    ```
    Enter `yes` at the prompt to confirm.


## Cleanup

To avoid incurring future costs, you can destroy all the resources created by this project.

1.  **Destroy Resources**
    Run the `destroy` command from the `terraform` directory.
    ```bash
    terraform destroy
    ```
    Enter `yes` at the prompt to confirm the deletion of all resources.

## Inputs

You can override the following variables by creating a `terraform.tfvars` file or by using the `-var` command-line argument:

- **`region`**
  - **Description**: The AWS region where the resources will be deployed.
  - **Type**: `string`
  - **Default**: `"us-east-1"`

- **`resource_suffix`**
  - **Description**: A suffix added to all resource names to differentiate between environments.
  - **Type**: `string`
  - **Default**: `"automqlab"`

- **`node_group`**
  - **Description**: Configuration for the EKS node group. You can customize the instance type, scaling parameters, and other settings as needed.
  - **Type**: `object`
  - **Default**:
    ```hcl
    {
      name          = "automq-node-group"
      desired_size  = 4
      max_size      = 10
      min_size      = 3
      instance_type = "c6g.2xlarge"
      ami_type      = "AL2_ARM_64"
    }
    ```

## Outputs

Upon successful deployment, Terraform will display the following outputs. You can also retrieve them at any time using the `terraform output` command:

| Name                            | Description                                           |
| ------------------------------- | ------------------------------------------------------- |
| `console_endpoint`              | The endpoint URL for the AutoMQ BYOC Console.                 |
| `initial_username`              | The initial username for logging into the Console.                       |
| `initial_password`              | The initial password for logging into the Console.                         |
| `cluster_name`                  | The name of the created EKS cluster.                          |
| `node_group_instance_profile_arn` | The IAM Instance Profile ARN used by the EKS node group.  |
| `dns_zone_id`                   | The Route 53 DNS Zone ID created for the BYOC environment.       |