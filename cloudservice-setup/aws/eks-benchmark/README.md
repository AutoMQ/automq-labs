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
│ │   AutoMQ    │ │◄───┤ │ Benchmark    │ │    │ │ Prometheus  │ │
│ │   Console   │ │    │ │ Workloads    │ │    │ │             │ │
│ └─────────────┘ │    │ └──────────────┘ │    │ └─────────────┘ │
│                 │    │                  │    │                 │
│ ┌─────────────┐ │    │                  │    │ ┌─────────────┐ │
│ │   AutoMQ    │ │    │                  │    │ │   Grafana   │ │
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

## Configuration

### Benchmark Node Configuration

Key parameters in `terraform/benchmark-node/terraform.tfvars`:

```hcl
# EKS Cluster Configuration
cluster_name              = "your-cluster-name"
existing_node_role_name   = "your-node-role"
aws_region               = "us-east-1"

# Node Group Configuration
resource_suffix    = "observability"
capacity_type     = "ON_DEMAND"
instance_types    = ["c5.xlarge", "m5.xlarge"]
desired_size      = 2
max_size          = 5
min_size          = 1

# Enable dedicated nodes for benchmarking
enable_dedicated_nodes = true
```

### Benchmark Test Configuration

Key parameters in `helm-chart/automq-benchmark/values.yaml`:

```yaml
# AutoMQ connection
automq:
  bootstrapServer: "automq-release-kafka.automq.svc.cluster.local:9092"
  securityProtocol: "PLAINTEXT"

# Test topology
benchmark:
  topics: 10
  partitionsPerTopic: 128
  producersPerTopic: 1
  recordSize: 52224
  sendRate: 160
  testDuration: 300  # 5 minutes
```

### Monitoring Configuration

The monitoring stack includes:
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **Remote Write**: Integration with AutoMQ metrics

## Observability Features

### Metrics Collection
- **AutoMQ Metrics**: Throughput, latency, partition metrics
- **Kubernetes Metrics**: Pod, node, and cluster resource usage
- **Benchmark Metrics**: Test results and performance indicators

### Pre-configured Dashboards
- **AutoMQ Cluster Overview**: Cluster health and performance
- **Benchmark Results**: Real-time test metrics and trends
- **Infrastructure Monitoring**: EKS cluster and node metrics

### Alerting (Optional)
Configure alerts for:
- High latency or low throughput
- Resource exhaustion
- Benchmark test failures

## Troubleshooting

### Common Issues

1. **Node Group Creation Fails**:
   - Verify IAM role permissions
   - Check subnet availability and capacity
   - Ensure EKS cluster is accessible

2. **AutoMQ Connection Issues**:
   - Verify service discovery and networking
   - Check security group configurations
   - Validate AutoMQ instance status

3. **Benchmark Job Fails**:
   - Check resource limits and node capacity
   - Verify AutoMQ connectivity
   - Review job logs for specific errors

4. **Grafana Access Issues**:
   - Verify LoadBalancer service creation
   - Check security group rules for port 80
   - Confirm Grafana pod is running

### Useful Commands

```bash
# Check EKS node groups
aws eks describe-nodegroup --cluster-name <cluster-name> --nodegroup-name <nodegroup-name>

# Verify AutoMQ pods
kubectl get pods -n automq

# Check benchmark job status
kubectl describe job automq-benchmark

# View Prometheus targets
kubectl port-forward -n prometheus svc/prometheus-kube-prometheus-prometheus 9090:9090

# Access Grafana locally
kubectl port-forward -n prometheus svc/prometheus-grafana 3000:80
```

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
- Contact the AutoMQ team for enterprise support

## License

This project is part of the AutoMQ Labs repository. Please refer to the main repository license for terms and conditions.