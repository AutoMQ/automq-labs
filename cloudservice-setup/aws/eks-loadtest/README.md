# EKS Load Test & Observability Setup

This project provides a complete solution for deploying load testing and observability infrastructure on an **existing** Amazon EKS cluster. It combines Terraform for infrastructure provisioning and Helm for application deployment to create a dedicated environment for performance testing and monitoring.

## Architecture

This setup consists of two main phases:

1. **Infrastructure Phase (Terraform)**: Provisions a dedicated EKS node group optimized for load testing and observability workloads
2. **Application Phase (Helm)**: Deploys monitoring stack (Prometheus + Grafana) and load testing infrastructure

### Components

**Infrastructure (Terraform)**:
- **Dedicated EKS Node Group**: Creates a new node group specifically for load testing and observability workloads
- **Instance Optimization**: Uses compute-optimized instances with SPOT pricing for cost efficiency
- **Workload Isolation**: Configures node taints and labels to ensure proper workload placement
- **Auto-scaling**: Supports dynamic scaling based on workload demands

**Applications (Helm)**:
- **Prometheus Stack**: Complete monitoring solution with Prometheus server and Grafana dashboard
- **Load Test Pod**: Ubuntu-based container with Java and testing tools pre-installed
- **Network Load Balancer**: External access to Grafana dashboard via AWS NLB
- **Persistent Storage**: Optional persistent volumes for data retention

## Prerequisites

Before you begin, ensure you have the following:

**Tools:**
- [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli) (v1.3.0+)
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) for cluster interaction
- [Helm](https://helm.sh/docs/intro/install/) (v3.0+) for application deployment

**AWS Resources:**
- An **existing EKS cluster** with kubectl access configured
- **VPC subnets** with sufficient IP addresses for new nodes
- **IAM permissions** for EKS node group management

**Required Information:**
- EKS cluster name
- Existing node group IAM role name
- VPC subnet IDs for node placement

## Quick Start

### Phase 1: Infrastructure Setup (Terraform)

#### Step 1: Prepare Terraform Configuration

1. **Navigate to the terraform directory**
   ```bash
   cd terraform
   ```

2. **Create configuration file**
   Copy the example configuration and customize it for your environment:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

3. **Edit terraform.tfvars**
   Update the file with your specific values:
   ```hcl
   # Required Variables
   cluster_name                  = "your-existing-cluster-name"
   existing_node_group_role_name = "your-cluster-node-group-role"
   subnet_ids                    = ["subnet-xxxxxxxxx", "subnet-yyyyyyyyy"]
   resource_suffix               = "loadtest-001"
   
   # Optional Configuration
   aws_region                    = "us-west-2"
   capacity_type                 = "SPOT"
   desired_size                  = 3
   max_size                      = 10
   min_size                      = 1
   ```

#### Step 2: Get Existing Cluster Information

If you're unsure about your cluster details, use these commands:

```bash
# List EKS clusters
aws eks list-clusters --region us-west-2

# Get cluster details
aws eks describe-cluster --name your-cluster-name --region us-west-2

# List existing node groups
aws eks list-nodegroups --cluster-name your-cluster-name --region us-west-2

# Get node group details (including IAM role)
aws eks describe-nodegroup --cluster-name your-cluster-name --nodegroup-name system-nodes --region us-west-2
```

#### Step 3: Deploy Node Group

```bash
# Initialize Terraform
terraform init

# Review execution plan
terraform plan

# Apply configuration
terraform apply
```

#### Step 4: Verify Node Group Deployment

```bash
# Check node group status
aws eks describe-nodegroup --cluster-name your-cluster-name --nodegroup-name loadtest-nodes-your-suffix --region us-west-2

# View nodes with kubectl
kubectl get nodes --show-labels

# Check load test specific nodes
kubectl get nodes -l workload-type=loadtest
```

### Phase 2: Application Deployment (Helm)

#### Step 5: Deploy Monitoring Stack

1. **Add Prometheus Helm repository**
   ```bash
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm repo update
   ```

2. **Deploy Prometheus and Grafana**
   ```bash
   # Create monitoring namespace
   kubectl create namespace prometheus

   # Deploy using custom values
   helm install prometheus prometheus-community/kube-prometheus-stack \
     --namespace prometheus \
     --values helm-values/monitoring/prometheus.yaml
   ```

3. **Verify monitoring deployment**
   ```bash
   # Check pods status
   kubectl get pods -n prometheus

   # Check services (including LoadBalancer)
   kubectl get svc -n prometheus
   ```

#### Step 6: Deploy Load Test Infrastructure

```bash
# Deploy load test pod
kubectl apply -f helm-values/loadtest/load-test.yaml

# Check pod status
kubectl get pods -l app=load-test

# Access load test pod
kubectl exec -it load-test-pod -- /bin/bash
```

#### Step 7: Access Grafana Dashboard

1. **Get Grafana LoadBalancer URL**
   ```bash
   kubectl get svc prometheus-grafana -n prometheus
   ```

2. **Access Grafana**
   - **URL**: Use the EXTERNAL-IP from the LoadBalancer service
   - **Username**: `admin`
   - **Password**: `Auto&mq1314` (as configured in prometheus.yaml)

## Configuration Options

### Terraform Variables

#### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `cluster_name` | Existing EKS cluster name | `"my-eks-cluster"` |
| `existing_node_group_role_name` | Existing node group IAM role name | `"eks-cluster-node-group-role"` |
| `subnet_ids` | List of subnet IDs for node placement | `["subnet-abc123", "subnet-def456"]` |
| `resource_suffix` | Suffix for resource naming | `"loadtest-001"` |

#### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region for deployment | `"us-west-2"` |
| `environment` | Environment tag | `"development"` |
| `capacity_type` | Instance capacity type | `"SPOT"` |
| `instance_types` | List of instance types | `["c5.large", "c5.xlarge", "m5.large", "m5.xlarge"]` |
| `desired_size` | Desired number of nodes | `3` |
| `max_size` | Maximum number of nodes | `10` |
| `min_size` | Minimum number of nodes | `1` |
| `enable_dedicated_nodes` | Enable node taints for workload isolation | `false` |
| `create_separate_iam_role` | Create separate IAM role with observability permissions | `false` |
| `node_group_ami_type` | AMI type for nodes | `"AL2_x86_64"` |
| `disk_size` | Node disk size in GiB | `50` |

### Helm Configuration

#### Monitoring Stack (prometheus.yaml)

- **Grafana**: Configured with LoadBalancer service for external access
- **Prometheus**: Enabled with remote write receiver for external metrics
- **Node Selector**: Targets load test nodes specifically
- **Persistence**: Disabled by default for cost optimization

#### Load Test Pod (load-test.yaml)

- **Base Image**: Ubuntu 22.04 for maximum compatibility
- **Pre-installed Tools**: Java 17, wget, curl, vim
- **Resource Limits**: Configurable CPU and memory limits
- **Node Placement**: Automatically scheduled on load test nodes

## Usage Scenarios

### 1. Basic Load Testing Setup

For general load testing with monitoring:

```hcl
# terraform.tfvars
enable_dedicated_nodes = false
create_separate_iam_role = false
capacity_type = "SPOT"
desired_size = 3
```

### 2. Dedicated Load Testing Environment

For isolated load testing with dedicated nodes:

```hcl
# terraform.tfvars
enable_dedicated_nodes = true
create_separate_iam_role = false
capacity_type = "ON_DEMAND"
```

Add tolerations to your load test applications:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-load-test
spec:
  template:
    spec:
      nodeSelector:
        workload-type: loadtest
      tolerations:
      - key: workload-type
        operator: Equal
        value: loadtest
        effect: NoSchedule
```

### 3. Enhanced Observability Setup

For comprehensive monitoring with additional CloudWatch permissions:

```hcl
# terraform.tfvars
create_separate_iam_role = true
enable_dedicated_nodes = true
```

## Outputs

After successful deployment, you'll have access to:

### Terraform Outputs

- `loadtest_node_group_name`: Name of the created node group
- `loadtest_node_group_arn`: ARN of the node group
- `node_selector_labels`: Labels for Kubernetes node selection
- `tolerations`: Required tolerations for dedicated nodes (if enabled)

### Application Access

- **Grafana Dashboard**: Available via LoadBalancer external IP
- **Load Test Pod**: Accessible via `kubectl exec`
- **Prometheus**: Internal cluster access for metrics collection

## Load Testing with the Setup

### Accessing the Load Test Pod

```bash
# Enter the load test pod
kubectl exec -it load-test-pod -- /bin/bash

# Verify installed tools
java -version
wget --version
```

### Running Load Tests

The load test pod comes with Java 17 and common tools pre-installed. You can:

1. **Download and run Kafka load testing tools**
2. **Install additional testing frameworks** (JMeter, Artillery, etc.)
3. **Run custom load testing scripts**
4. **Monitor performance** via Grafana dashboards

### Monitoring Performance

1. **Access Grafana** using the LoadBalancer URL
2. **Import Kubernetes dashboards** for cluster monitoring
3. **Create custom dashboards** for your specific metrics
4. **Set up alerts** for performance thresholds

## Cleanup

### Remove Applications

```bash
# Remove load test pod
kubectl delete -f helm-values/loadtest/load-test.yaml

# Remove monitoring stack
helm uninstall prometheus -n prometheus
kubectl delete namespace prometheus
```

### Remove Infrastructure

```bash
# Navigate to terraform directory
cd terraform

# Destroy node group and related resources
terraform destroy

# Confirm deletion
# Enter "yes" when prompted
```

**Note**: This will only remove the load test node group and related resources. Your existing EKS cluster and other infrastructure will remain intact.

## Troubleshooting

### Infrastructure Issues

#### 1. IAM Permission Problems

Ensure your AWS credentials have the following permissions:
- `eks:*`
- `ec2:*`
- `iam:GetRole`
- `iam:PassRole`

#### 2. Subnet Configuration Issues

Verify that specified subnets:
- Belong to the EKS cluster's VPC
- Have sufficient available IP addresses
- Are configured with appropriate route tables

#### 3. Node Group Creation Failures

Check:
- Cluster name accuracy
- IAM role name existence
- Subnet ID validity
- Instance type availability in the region

### Application Issues

#### 1. Pods Not Scheduling

If pods remain in `Pending` state:
- Check node selector labels match
- Verify tolerations are correctly configured
- Ensure sufficient node capacity

#### 2. Grafana LoadBalancer Issues

If LoadBalancer doesn't get an external IP:
- Verify AWS Load Balancer Controller is installed
- Check subnet tags for load balancer discovery
- Review security group configurations

#### 3. Monitoring Data Issues

If metrics aren't appearing:
- Verify Prometheus is scraping targets
- Check network policies aren't blocking traffic
- Ensure proper RBAC permissions

## Security Considerations

### Network Security

- **LoadBalancer Access**: Grafana is exposed via internet-facing NLB
- **Internal Communication**: Prometheus uses cluster-internal networking
- **Pod Security**: Load test pod runs with root privileges for tool installation

### Access Control

- **Grafana Authentication**: Default admin credentials should be changed
- **Kubernetes RBAC**: Ensure proper role-based access control
- **AWS IAM**: Follow principle of least privilege for node group roles

### Recommendations

1. **Change default Grafana password** after first login
2. **Configure network policies** to restrict pod-to-pod communication
3. **Use AWS security groups** to limit LoadBalancer access
4. **Enable audit logging** for cluster activities
5. **Regularly update** container images and Helm charts

## Related Documentation

- [Amazon EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [EKS Managed Node Groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html)
- [Prometheus Operator](https://prometheus-operator.dev/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Kubernetes Node Selectors](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector)
- [Kubernetes Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [Helm Charts](https://helm.sh/docs/topics/charts/)