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

-   **VPC**: A dedicated Virtual Private Cloud (VPC) to isolate the network resources (or use an existing VPC).
-   **EKS Cluster**: A managed Kubernetes cluster control plane.
-   **EKS Node Group**: A group of EC2 instances that will serve as the worker nodes for the Kubernetes cluster. The instance type and scaling options can be configured in `main.tf`.
-   **IAM Roles and Policies**: The necessary permissions for the EKS control plane and worker nodes to function correctly and access resources like S3.

## Configuration Options

### Option 1: Create New VPC (Default)

By default, this Terraform configuration will create a new VPC with the necessary subnets, NAT gateway, and endpoints.

### Option 2: Use Existing VPC

You can configure this setup to use an existing VPC by setting the following variables:

```hcl
use_existing_vpc            = true
existing_vpc_id             = "vpc-xxxxxxxxxxxxxxxxx"
existing_private_subnet_ids = ["subnet-xxx", "subnet-yyy", "subnet-zzz"]
existing_public_subnet_ids  = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]  # Optional
```

### Option 3: Use Existing VPC + Create NAT Gateway

If your existing VPC doesn't have a NAT Gateway configured, you can create one:

```hcl
use_existing_vpc            = true
create_nat_gateway          = true
existing_vpc_id             = "vpc-xxxxxxxxxxxxxxxxx"
existing_private_subnet_ids = ["subnet-xxx", "subnet-yyy", "subnet-zzz"]
existing_public_subnet_ids  = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]  # Required when create_nat_gateway is true
```

**Requirements for existing VPC:**
- The VPC must have DNS hostnames and DNS support enabled
- Private subnets must have internet access (via NAT Gateway or similar)
- When `create_nat_gateway` is true, at least one public subnet is required
- At least one private subnet is required for EKS node groups
- Subnets should be in different Availability Zones for high availability

## Usage

**Prerequisites**

-   **AWS CLI**: Ensure you have the AWS CLI installed and configured with appropriate credentials.

### Quick Start

1.  **Initialize Terraform**:
    ```bash
    terraform init
    ```

2.  **Configure variables** (Optional):
    
    Copy the example variables file and customize as needed:
    ```bash
    cp terraform.tfvars.example terraform.tfvars
    # Edit terraform.tfvars with your preferred settings
    ```

3.  **Review the plan**:
    ```bash
    terraform plan
    ```

4.  **Apply the configuration**:
    ```bash
    terraform apply
    ```

After the apply is complete, Terraform will output the cluster name, VPC ID, and the AWS region.

### Using Existing VPC

To use an existing VPC, create a `terraform.tfvars` file with the following content:

```hcl
region = "ap-northeast-1"
resource_suffix = "automqlab"

use_existing_vpc = true
existing_vpc_id = "vpc-0123456789abcdef0"
existing_private_subnet_ids = [
  "subnet-0123456789abcdef0",
  "subnet-0123456789abcdef1",
  "subnet-0123456789abcdef2"
]
existing_public_subnet_ids = [
  "subnet-0123456789abcdef3",
  "subnet-0123456789abcdef4",
  "subnet-0123456789abcdef5"
]
```

Then run:
```bash
terraform init
terraform plan
terraform apply
```