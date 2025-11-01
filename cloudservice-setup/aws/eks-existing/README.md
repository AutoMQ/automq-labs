# AutoMQ BYOC on Existing Amazon EKS Cluster

This document provides instructions for deploying an AutoMQ BYOC (Bring Your Own Cloud) environment on an **existing** Amazon EKS (Elastic Kubernetes Service) cluster using Terraform.

This project automates the setup process detailed in the [official AutoMQ documentation](https://www.automq.com/docs/automq-cloud/deploy-automq-on-kubernetes/deploy-to-aws-eks), providing a repeatable and efficient way to configure an existing EKS cluster for AutoMQ deployment.

## Architecture

This Terraform project configures an **existing** AWS EKS cluster for AutoMQ BYOC deployment. It provisions and configures the following resources:

1.  **AutoMQ BYOC Environment**: Uses the official `AutoMQ/automq-byoc-environment/aws` module to deploy the AutoMQ Console within your existing VPC. The Console serves as the central management plane for your message queues.

2.  **Dedicated EKS Node Group**: Creates a new node group specifically for AutoMQ workloads with the following characteristics:
    *   Uses compute-optimized instances (default: `c6g.2xlarge` with AWS Graviton2 processors)
    *   Configured with node taints (`dedicated=automq:NoSchedule`) to ensure workload isolation
    *   Auto-scaling capabilities (default: 3-10 nodes, desired: 4)

3.  **Essential EKS Add-ons**: Automatically installs and configures critical add-ons for full cluster functionality:
    *   **AWS Load Balancer Controller**: Manages AWS Application Load Balancers (ALB) and Network Load Balancers (NLB) for Kubernetes services of type `LoadBalancer`. This enables automatic provisioning of load balancers when services are created.
    *   **Amazon EBS CSI Driver**: Allows Kubernetes to dynamically provision, attach, and manage Amazon EBS volumes as persistent storage for pods. Essential for stateful workloads that require persistent data storage.
    *   **Cluster Autoscaler**: Automatically adjusts the number of worker nodes in your EKS cluster based on resource demands. It scales out when pods can't be scheduled due to insufficient resources and scales in when nodes are underutilized.
    *   **AWS VPC CNI**: Provides native AWS networking capabilities, allowing pods to receive IP addresses directly from your VPC subnets for improved network performance and security.

4.  **IAM Roles & Permissions**: Creates and configures comprehensive IAM roles and policies:
    *   **EKS Node Group Role**: Grants worker nodes permissions for ECR (container registry access), CNI operations, and worker node management
    *   **Service Account Roles (IRSA)**: Individual IAM roles for each add-on (EBS CSI Driver, Load Balancer Controller, Cluster Autoscaler) following the principle of least privilege
    *   **AutoMQ-specific permissions**: Roles for S3 bucket access and virtual machine (VM) management

  5.  **Security and Access Configuration**:
    *   **Security Group Rules**: Configures network access rules to allow secure communication between the AutoMQ Console and your EKS cluster
    *   **EKS Access Entry**: Grants the AutoMQ Console's IAM role administrative privileges over the cluster using the new EKS Access Management feature, enabling it to deploy and manage AutoMQ workloads
    *   **Cluster Admin Policy**: Associates the `AmazonEKSClusterAdminPolicy` with the AutoMQ Console role for full cluster management capabilities

## Prerequisites

Before you begin, ensure you have the following:

**Tools:**
*   [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli) (v1.0.0+)
*   [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
*   [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) for cluster interaction

**AWS Resources:**
*   An **existing EKS cluster** that you want to configure for AutoMQ
*   A **VPC** with both public and private subnets. To ensure S3 traffic remains within the VPC (and not over the public internet), the VPC must have an S3 Gateway Endpoint.
*   **Private subnets** for the EKS node group (at least one). These subnets must have a route to the public internet (e.g., via a NAT Gateway) to allow nodes to pull container images.
*   A **public subnet** for the AutoMQ Console deployment


## Usage

### Step 1: Prepare Your Configuration

1.  **Create a `terraform.tfvars` file**
    Copy the example configuration and update it with your existing infrastructure details:
    ```bash
    cp terraform/terraform.tfvars terraform/terraform.tfvars
    ```
    
    Edit the file with your specific values:
    ```hcl
    eks_cluster_name     = "my-existing-cluster"
    vpc_id              = "vpc-abc123def456"
    private_subnet_ids  = ["subnet-private1", "subnet-private2"] 
    console_subnet_id   = "subnet-public1"
    region              = "us-west-2"
    resource_suffix     = "prod"
    ```

### Step 2: Initialize and Deploy

1.  **Initialize Terraform**
    Navigate to the terraform directory and initialize the workspace:
    ```bash
    cd terraform
    terraform init
    ```


### Required Inputs

This project requires several inputs to connect to your existing infrastructure. Create a `terraform.tfvars` file with the following variables:

```hcl
# Required - Your existing infrastructure
eks_cluster_name     = "your-existing-cluster-name"
vpc_id              = "vpc-xxxxxxxxx"
private_subnet_ids  = ["subnet-xxxxxxxxx", "subnet-yyyyyyyyy"]  # For node group
console_subnet_id   = "subnet-zzzzzzzzz"                        # Public subnet for AutoMQ Console

# Optional - Customize as needed
region           = "us-east-1"
resource_suffix  = "automqlab"
```

### Configurable Inputs

You can customize the following variables:

- **`region`**
  - **Description**: The AWS region where the resources will be deployed.
  - **Type**: `string`
  - **Default**: `"us-east-1"`

- **`resource_suffix`**
  - **Description**: A suffix added to all resource names to differentiate between environments.
  - **Type**: `string`
  - **Default**: `"automqlab"`

- **`eks_cluster_name`** *(Required)*
  - **Description**: Name of your existing EKS cluster to configure for AutoMQ.
  - **Type**: `string`

- **`vpc_id`** *(Required)*
  - **Description**: VPC ID where your existing EKS cluster is deployed.
  - **Type**: `string`

- **`private_subnet_ids`** *(Required)*
  - **Description**: List of private subnet IDs for the EKS node group deployment.
  - **Type**: `list(string)`

- **`console_subnet_id`** *(Required)*
  - **Description**: Public subnet ID for the AutoMQ Console deployment.
  - **Type**: `string`

- **`node_group`**
  - **Description**: Configuration for the dedicated AutoMQ node group.
  - **Type**: `object`
  - **Default**:
    ```hcl
    {
      name          = "automq-node-group"
      desired_size  = 4
      max_size      = 10
      min_size      = 3
      instance_type = "c6g.2xlarge"    # AWS Graviton2 processor
      ami_type      = "AL2_ARM_64"     # Amazon Linux 2 ARM64
    }
    ```

- **EKS Add-ons Configuration** (all default to `true`):
  - `enable_autoscaler`: Enable Kubernetes Cluster Autoscaler
  - `enable_alb_ingress_controller`: Enable AWS Load Balancer Controller  
  - `enable_vpc_cni`: Enable AWS VPC CNI
  - `enable_ebs_csi_driver`: Enable AWS EBS CSI Driver


2.  **Plan the Deployment**
    Review what resources will be created and modified:
    ```bash
    terraform plan
    ```

3.  **Apply the Configuration**
    Deploy the AutoMQ configuration to your existing cluster:
    ```bash
    terraform apply
    ```
    Enter `yes` when prompted. The deployment typically takes 10-15 minutes and includes:
    - Installing EKS add-ons (Load Balancer Controller, EBS CSI Driver, etc.)
    - Creating the AutoMQ-dedicated node group
    - Deploying the AutoMQ Console
    - Configuring cluster access and security

### Outputs

Upon successful deployment, Terraform will display the following outputs. You can retrieve them anytime using `terraform output`:

| Name                              | Description                                           |
| --------------------------------- | ----------------------------------------------------- |
| `console_endpoint`                | The endpoint URL for accessing the AutoMQ BYOC Console |
| `initial_username`                | The initial username for logging into the Console      |
| `initial_password`                | The initial password for logging into the Console      |
| `cluster_name`                    | The name of your configured EKS cluster               |
| `node_group_instance_profile_arn` | The IAM Instance Profile ARN for the AutoMQ node group |
| `dns_zone_id`                     | The Route 53 DNS Zone ID created for the BYOC environment |


## Next Steps

After provisioning the infrastructure, the final step is to configure your profile. Please follow the instructions in **Step 12** of the official AutoMQ deployment guide:

- **[Deploy AutoMQ on AWS EKS: Enter the Environment Console and Create Deployment Configurations](https://www.automq.com/docs/automq-cloud/deploy-automq-on-kubernetes/deploy-to-aws-eks#step-12-access-the-environment-console-and-create-deployment-configuration)**


## Cleanup

To remove the AutoMQ configuration from your EKS cluster while preserving the cluster itself:

1.  **Destroy AutoMQ Resources**
    Run the destroy command from the `terraform` directory:
    ```bash
    terraform destroy
    ```
    Enter `yes` to confirm the deletion.

**Note**: This will only remove the AutoMQ-specific resources (node group, add-ons, Console, IAM roles) and will **NOT** delete your existing EKS cluster or VPC infrastructure.
