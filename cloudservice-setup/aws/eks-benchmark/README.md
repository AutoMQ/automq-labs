# AutoMQ EKS Benchmark & Observability

This project extends the existing AutoMQ EKS demo by adding comprehensive observability and performance benchmarking capabilities. It enables you to deploy monitoring infrastructure and conduct performance testing on existing AutoMQ clusters running on Amazon EKS, with real-time visualization through observability dashboards.

## Overview

The project provides:

- **Infrastructure Setup**: Terraform modules for deploying dedicated benchmark nodes on existing EKS clusters
- **AutoMQ Integration**: Automated deployment and configuration of AutoMQ instances with monitoring integration
- **Observability Stack**: Prometheus and Grafana deployment for comprehensive monitoring and visualization
- **Benchmark Tools**: Helm charts for running performance tests against AutoMQ clusters
- **Dashboard Visualization**: Pre-configured Grafana dashboards to visualize benchmark results and cluster metrics

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   EKS Cluster   │    │  Benchmark Nodes │    │ Observability   │
│                 │    │                  │    │                 │
│ ┌─────────────┐ │    │ ┌──────────────┐ │    │ ┌─────────────┐ │
│ │   AutoMQ    │ │    │ │ Benchmark    │ │    │ │ Prometheus  │ │
│ │   Console   │ │    │ │ Workloads    │ │    │ │             │ │
│ └─────────────┘ │    │ └──────┬───────┘ │    │ └─────────────┘ │
│                 │    │        │         │    │                 │
│ ┌─────────────┐ │    │        │         │    │ ┌─────────────┐ │
│ │   AutoMQ    │ │◄────────────┘         │    │ │   Grafana   │ │
│ │   Cluster   │ │    │                  │    │ │ Dashboards  │ │
│ └─────────────┘ │    │                  │    │ └─────────────┘ │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

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

2. **Deploy benchmark nodes**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

### Step 2: Deploy AutoMQ Instance (Optional)

This optional step allows you to deploy additional AutoMQ instances if needed for your testing scenario. It uses the AutoMQ BYOC provider to create and configure AutoMQ clusters with integrated monitoring capabilities, including Prometheus remote write endpoints for metrics collection.

**Expected Result**: A new AutoMQ instance will be deployed and configured with monitoring integration, ready to handle Kafka workloads and export metrics to your observability stack.

If you need to deploy additional AutoMQ instances:

1. **Configure AutoMQ deployment**:
   ```bash
   cd terraform/automq
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your AutoMQ BYOC credentials
   ```

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
   ```bash
   # Get Grafana LoadBalancer URL
   kubectl get svc -n prometheus prometheus-grafana
   
   # Default credentials:
   # Username: admin
   # Password: AutoMQ@Grafana
   ```

### Step 4: Run Benchmark Tests

This step executes performance tests against your AutoMQ cluster using configurable workloads. The benchmark simulates real-world Kafka usage patterns with customizable parameters for throughput, message size, topic configuration, and test duration. The tests generate comprehensive metrics that are automatically collected by your monitoring stack.

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