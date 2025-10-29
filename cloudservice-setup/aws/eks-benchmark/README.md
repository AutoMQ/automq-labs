# AutoMQ Quick Setup & Benchmark

Deploying a complete AutoMQ cluster on AWS traditionally involves multiple, complex steps, from setting up the control and data planes to manually configuring a separate observability environment and benchmarking tools.

This project eliminates that complexity. It is designed to provide a seamless, one-click solution using Terraform to automatically provision an entire AutoMQ ecosystem on AWS.

The primary goal is to empower users to effortlessly spin up a fully operational, observable, and testable AutoMQ cluster, drastically reducing setup time and manual configuration.

## Overview
 
This project follows a simple, three-step end-to-end flow to go from infrastructure to benchmarking with minimal manual work:

1) Provision with Terraform: bring up the required components — `EKS`, `AutoMQ Console` (BYOC control plane), and the observability stack (Prometheus/Grafana). After this step, the Kubernetes cluster and monitoring environment are ready.

2) Configure in AutoMQ Console and create the cluster: create the required `Profile` and credentials in the Console, then create or connect your `AutoMQ Cluster` (BYOC). Use these values in the subsequent Terraform/Helm configuration to enable connectivity.

3) Run benchmarks via the provided Helm chart: go to `helm-chart/automq-benchmark`, set connection details and workload parameters (topics, partitions, message size, concurrency, etc.), deploy the benchmark Job, and observe throughput and latency in Grafana.



## Architecture

![architecture](./architecture.png)

## Prerequisites

Before using this project, ensure you have:

### Required Tools
- **Terraform** (>= 1.0)
- **kubectl** configured for your EKS cluster
- **Helm** (>= 3.0)
- **AWS CLI** configured with appropriate permissions

### Required Permissions

- EKS cluster management permissions
- EC2 instance and networking permissions
- IAM role management permissions
- S3 bucket access (for AutoMQ data storage)

## Quick Start

### Step 1: Deploy Benchmark Infrastructure

This step provisions and integrates everything via Terraform in `./eks-benchmark/terraform`:

- EKS cluster (creating and configuring required `VPC`, subnets, `Security Group`, `IAM`, and related networking/permission resources)
- AutoMQ BYOC Console (deployed in the same VPC public subnet, with access and security integrated to the EKS cluster)
- Observability stack (Prometheus/Grafana) installed via Helm `kube-prometheus-stack` for collecting and visualizing benchmark metrics

All necessary cloud resources (including networking and object storage such as `S3`) will be newly created and wired up in this step.

1. Plan the Deployment Run terraform plan to preview the resources that will be created.

Tip: To control resource naming and avoid conflicts, set `resource_suffix` in `terraform/variables.tf`.

```bash
terraform plan
```

2. Apply the Deployment After reviewing the plan, execute terraform apply to begin the deployment. This process may take 25-30 minutes.

```bash
terraform apply
```

Enter yes at the prompt to confirm.


### Step 2: Deploy AutoMQ Instance

1. Follow [Create a Service Account](https://www.automq.com/docs/automq-cloud/manage-identities-and-access/service-accounts#create-a-service-account) to create a Service Account and obtain the `Client ID` and `Client Secret` (used as `automq_byoc_access_key_id` and `automq_byoc_secret_key`).

2. In the AutoMQ Console, create a Deploy Profile for the EKS environment (e.g., named `eks`). Reference: [Create a Deploy Profile](https://www.automq.com/docs/automq-cloud/deploy-automq-on-kubernetes/deploy-to-aws-eks#step-12%3A-access-the-environment-console-and-create-deployment-configuration).

3. Fill variables `automq/terraform.tfvars` and apply Terraform to create the AutoMQ cluster with observability integration. You may need to wait approximately 5 to 10 minutes for the cluster to be fully created.

```bash
terraform init
terraform apply
```

#### AutoMQ tfvars Parameters

Use the following variables in `cloudservice-setup/aws/eks-benchmark/automq/terraform.tfvars` to connect Terraform to your AutoMQ Console and environment:

| Parameter | Description | Notes |
| - | - | - |
| `automq_byoc_endpoint` | AutoMQ BYOC Console API endpoint | Get from output of step1 |
| `automq_byoc_access_key_id` | BYOC API Access Key (Client ID) | Paired with `automq_byoc_secret_key`; do not commit secrets |
| `automq_byoc_secret_key` | BYOC API Secret Key (Client Secret) | Keep locally and secure; avoid plaintext leaks |
| `automq_deploy_profile_name` | Deploy Profile name created in Console | Must exactly match the name created in Console |
| `automq_environment_id` | AutoMQ Environment ID | Get from the AutoMQ Console env page |


### Step 3: Run Benchmark Tests

This step executes performance tests against your AutoMQ cluster using configurable workloads. The benchmark simulates Kafka usage patterns with customizable parameters for throughput, message size, topic configuration, and test duration. The tests generate comprehensive metrics that are automatically collected by your monitoring stack.

For specific configurations of helm values, you can refer to the [README](./automq-benchmark-chart/README.md) in the automq-benchmark folder for further details.

**Expected Result**: Benchmark jobs will run and generate load against the AutoMQ cluster. Performance metrics including throughput, latency, and resource utilization will be collected and visible in Grafana dashboards. You should see data flowing through the system and performance characteristics of your AutoMQ deployment.

1. **Configure benchmark parameters**:

```bash
cd helm-chart/automq-benchmark
```

2. **Deploy benchmark workload**:

```bash
helm install automq-benchmark . \
  --namespace default \
  --values values.yaml
```

3. **View results in Grafana**:
   - Access your Grafana dashboard
   - Navigate to AutoMQ performance dashboards
   - Observe real-time metrics during the test execution

After completing the above steps, you can see the corresponding metrics on the Grafana dashboard. Adjust the stress test parameters according to the corresponding specifications to further understand the specifications and performance related to AutoMQ.



## Cleanup

To remove all deployed resources:

```bash
# Remove benchmark workload
helm uninstall automq-benchmark

# Remove AutoMQ instance
cd automq
terraform destroy

# Remove EKS and AutoMQ Console
cd terraform
terraform destroy
```