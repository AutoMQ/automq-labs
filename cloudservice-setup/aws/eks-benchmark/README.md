# AutoMQ Quick Setup & Benchmark

Deploying a complete AutoMQ cluster on AWS traditionally involves multiple, complex steps, from setting up the control and data planes to manually configuring a separate observability environment and benchmarking tools.

This project eliminates that complexity. It is designed to provide a seamless, one-click solution using Terraform to automatically provision an entire AutoMQ ecosystem on AWS.

The primary goal is to empower users to effortlessly spin up a fully operational, observable, and testable AutoMQ cluster, drastically reducing setup time and manual configuration.

## Overview

The project provides:

- **Infrastructure Setup**: Terraform modules for deploying dedicated benchmark nodes on existing EKS clusters
- **AutoMQ Integration**: Automated deployment and configuration of AutoMQ instances with monitoring integration
- **Observability Stack**: Prometheus and Grafana deployment for comprehensive monitoring and visualization
- **Benchmark Tools**: Helm charts for running performance tests against AutoMQ clusters
- **Dashboard Visualization**: Pre-configured Grafana dashboards to visualize benchmark results and cluster metrics

## Architecture

![architecture](./architecture.png)

## Prerequisites

Before using this project, ensure you have:

### Required Infrastructure
- **Existing EKS Cluster**: A running Amazon EKS cluster
- **AutoMQ Console**: AutoMQ Console already installed and configured
- **AutoMQ Cluster**: At least one AutoMQ cluster deployed and operational

> **Note**: You can refer to [`/cloudservice-setup/aws/eks/`](../eks/) for instructions on setting up a complete EKS cluster with AutoMQ Console using Terraform.


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

## Project Structure

```
eks-benchmark/
├── terraform/
│   ├── benchmark-node/          # Terraform module for benchmark nodes
│   │   ├── main.tf             # Node group configuration
│   │   ├── variables.tf        # Input variables
│   │   ├── outputs.tf          # Output values
│   │   └── terraform.tfvars.example
│   └── automq/                 # AutoMQ deployment configuration
│       ├── main.tf             # AutoMQ instance setup
│       └── terraform.tfvars.example
├── helm-chart/
│   └── automq-benchmark/       # Helm chart for benchmark workloads
│       ├── Chart.yaml
│       ├── values.yaml         # Benchmark configuration
│       └── templates/
├── monitoring/
│   └── prometheus.yaml         # Prometheus & Grafana configuration
└── README.md
```

## Quick Start

### Step 1: Deploy Benchmark Infrastructure

This step creates dedicated EKS node groups optimized for running benchmark workloads. These nodes are configured with appropriate instance types (4c8g minimum) and can be optionally tainted to ensure benchmark workloads run in isolation from other cluster workloads.

**Expected Result**: A new EKS node group will be created and ready to host benchmark pods, providing the computational resources needed for performance testing.

1. **Configure benchmark nodes**:
   ```bash
   cd terraform/benchmark-node
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your cluster details
   ```

   **Required Configuration Parameters**:
   
   You can override the following variables by creating a `terraform.tfvars` file or by using the `-var` command-line argument:

   - **`cluster_name`**
     - **Description**: The name of your existing EKS cluster where benchmark nodes will be deployed.
     - **Type**: `string`
     - **Required**: Yes
     - **How to find**: Use `kubectl config current-context` or check AWS EKS console

   - **`existing_node_role_name`**
     - **Description**: The IAM role name used by existing EKS node groups in your cluster.
     - **Type**: `string`
     - **Required**: Yes
     - **How to find**: Check your existing node group's IAM role in AWS EKS console

   - **`aws_region`**
     - **Description**: The AWS region where your EKS cluster is located and resources will be deployed.
     - **Required**: Yes
     - **Type**: `string`
     - **Default**: `"us-east-1"`

   - **`environment`**
     - **Description**: Environment tag used for resource identification and organization.
     - **Required**: Yes
     - **Type**: `string`
     - **Default**: `"dev"`

   - **`subnet_ids`**
     - **Description**: List of subnet IDs where benchmark nodes will be deployed. Recommend using only one subnet in us-east-1a for optimal performance.
     - **Type**: `list(string)`
     - **Required**: Yes

2. **Deploy benchmark nodes**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

### Step 2: Deploy AutoMQ Instance

Access the AutoMQ control plane obtained in the previous step to create access credentials aksk. In the current version, you also need to create an eks profile for further access to the cluster, which needs to be filled into the terraform variables. Future releases of AutoMQ will allow profile creation through terraform.

1. **Configure AutoMQ deployment**:
   ```bash
   cd terraform/automq
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your AutoMQ BYOC credentials
   ```

   **Required Configuration Parameters**:
   
   You can override the following variables by creating a `terraform.tfvars` file or by using the `-var` command-line argument:

   - **`vpc_id`**
     - **Description**: The VPC ID where your EKS cluster is deployed and AutoMQ resources will be created.
     - **Type**: `string`
     - **Required**: Yes
     - **How to find**: Check AWS VPC console or use `aws ec2 describe-vpcs` command

   - **`region`**
     - **Description**: The AWS region where AutoMQ resources will be deployed.
     - **Type**: `string`
     - **Default**: `"us-east-1"`

   - **`az`**
     - **Description**: The availability zone where AutoMQ resources will be deployed.
     - **Type**: `string`
     - **Default**: `"us-east-1a"`

   - **`automq_byoc_endpoint`**
     - **Description**: The AutoMQ BYOC (Bring Your Own Cloud) endpoint URL for API access.
     - **Type**: `string`
     - **Required**: Yes
     - **How to find**: Obtain from AutoMQ Console after setting up your BYOC environment

   - **`automq_byoc_access_key_id`**
     - **Description**: Access key ID for AutoMQ BYOC authentication.
     - **Type**: `string`
     - **Required**: Yes
     - **How to find**: Generate from AutoMQ Console credentials section

   - **`automq_byoc_secret_key`**
     - **Description**: Secret access key for AutoMQ BYOC authentication.
     - **Type**: `string`
     - **Required**: Yes
     - **How to find**: Generate from AutoMQ Console credentials section (keep secure)

   - **`automq_environment_id`**
     - **Description**: The AutoMQ environment identifier for resource organization.
     - **Type**: `string`
     - **Required**: Yes
     - **How to find**: Available in AutoMQ Console environment settings

2. **Deploy AutoMQ instance**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

### Step 3: Deploy Observability Stack

This step deploys a comprehensive monitoring solution including Prometheus and Grafana to collect, store, and visualize metrics from your AutoMQ cluster and benchmark workloads. The stack is configured with remote write capabilities and pre-configured dashboards for AutoMQ monitoring.

**Expected Result**: Prometheus and Grafana will be deployed and accessible via LoadBalancer services. Prometheus will start collecting metrics from AutoMQ instances, and Grafana will be ready to display performance dashboards.

1. **Install Prometheus and Grafana**:
   ```bash
   # Add Prometheus community Helm repository
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm repo update
   
   # Create monitoring namespace
   kubectl create namespace prometheus
   
   # Deploy Prometheus and Grafana
   helm install prometheus prometheus-community/kube-prometheus-stack \
     -n prometheus \
     -f monitoring/prometheus.yaml
   ```

2. **Access Grafana Dashboard**:

   You can access the Grafana dashboard in this way, and contact the AutoMQ team to obtain the [configuration file](https://www.automq.com/docs/automq/observability/dashboard-configuration) for the observability dashboard.

   ```bash
   kubectl get svc -n prometheus prometheus-grafana
   
   # Default credentials:

   ```

### Step 4: Run Benchmark Tests

This step executes performance tests against your AutoMQ cluster using configurable workloads. The benchmark simulates real-world Kafka usage patterns with customizable parameters for throughput, message size, topic configuration, and test duration. The tests generate comprehensive metrics that are automatically collected by your monitoring stack.

For specific configurations of helm values, you can refer to the [README](./helm-chart/automq-benchmark/README.md) in the automq-benchmark folder for further details.

**Expected Result**: Benchmark jobs will run and generate load against the AutoMQ cluster. Performance metrics including throughput, latency, and resource utilization will be collected and visible in Grafana dashboards. You should see data flowing through the system and performance characteristics of your AutoMQ deployment.



1. **Configure benchmark parameters**:
   ```bash
   cd helm-chart/automq-benchmark
   # Edit values.yaml to configure:
   # - AutoMQ connection details
   # - Test parameters (topics, partitions, message size, etc.)
   # - Resource requirements
   ```

2. **Deploy benchmark workload**:
   ```bash
   helm install automq-benchmark . \
     --namespace default \
     --values values.yaml
   ```

3. **Monitor benchmark progress**:
   ```bash
   # Watch job status
   kubectl get jobs -w
   
   # View benchmark logs
   kubectl logs -f job/automq-benchmark
   ```

4. **View results in Grafana**:
   - Access your Grafana dashboard
   - Navigate to AutoMQ performance dashboards
   - Observe real-time metrics during the test execution

> **Note**: For comprehensive dashboard configurations and additional monitoring templates, you can contact the AutoMQ team to obtain pre-configured Grafana dashboards that will help you visualize detailed performance metrics and system health indicators.



## Cleanup

To remove all deployed resources:

```bash
# Remove benchmark workload
helm uninstall automq-benchmark

# Remove monitoring stack
helm uninstall prometheus -n prometheus
kubectl delete namespace prometheus

# Remove AutoMQ instance (if deployed)
cd terraform/automq
terraform destroy

# Remove benchmark nodes
cd terraform/benchmark-node
terraform destroy
```

## Contributing

When contributing to this project:
1. Test changes in a development environment
2. Update documentation for any configuration changes
3. Ensure Terraform modules follow best practices
4. Validate Helm charts with different configurations

## Support

For issues and questions:
- Check the [AutoMQ Documentation](https://docs.automq.com)
- Review existing issues in the repository
- Contact the AutoMQ team for enterprise support, welcome to join our [Slack community](https://go.automq.com/slack)