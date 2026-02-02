# Deploy AutoMQ on AWS EKS with Strimzi

This guide provides step-by-step instructions for deploying AutoMQ on AWS EKS using the Strimzi Kafka Operator.

## Prerequisites

### 1. AWS EKS Cluster

You need an AWS EKS cluster with the following requirements:

- **Kubernetes Version**: 1.28+
- **Node Instance Type**: `r6i.large` or larger (16GB+ memory required)
- **Node Count**: At least 3 nodes for high availability
- **Storage Class**: `gp2` or `gp3` available

To provision an EKS cluster, follow our Terraform guide:
👉 [Terraform for AutoMQ on AWS EKS](../../../byoc-examples/setup/kubernetes/aws/terraform/README.md)

### 2. Tools

Ensure you have the following tools installed:

```bash
# Verify kubectl
kubectl version --client

# Verify helm
helm version

# Verify AWS CLI
aws --version
```

### 3. S3 Buckets

Create two S3 buckets for AutoMQ data storage:

```bash
# Set your AWS region
export AWS_REGION=us-east-1

# Create unique bucket names (add a random suffix)
export BUCKET_SUFFIX=$(date +%s)
export DATA_BUCKET="automq-data-${BUCKET_SUFFIX}"
export OPS_BUCKET="automq-ops-${BUCKET_SUFFIX}"

# Create buckets
aws s3 mb s3://${DATA_BUCKET} --region ${AWS_REGION}
aws s3 mb s3://${OPS_BUCKET} --region ${AWS_REGION}

echo "Data Bucket: ${DATA_BUCKET}"
echo "Ops Bucket: ${OPS_BUCKET}"
```

### 4. IAM Permissions

The EKS node group needs S3 access permissions. If you used our Terraform setup, the IAM role is already configured. Otherwise, attach the following policy to your node group IAM role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::automq-*",
        "arn:aws:s3:::automq-*/*"
      ]
    }
  ]
}
```

## Installation

### Step 1: Pre-flight Check

Run the pre-flight check to verify your cluster meets the requirements:

```bash
./install.sh --check
```

This will verify:
- kubectl and helm are installed
- Cluster connectivity
- Node instance types (r6i.large or larger)
- Available memory on nodes

### Step 2: Install Strimzi Operator

```bash
# Create namespace
kubectl create namespace automq

# Install Strimzi Operator
helm install automq-strimzi-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator \
  --version 0.47.0 \
  --namespace automq \
  --values strimzi-values.yaml

# Wait for operator to be ready
kubectl wait --for=condition=available deployment/strimzi-cluster-operator \
  -n automq --timeout=120s
```

### Step 3: Configure AutoMQ Cluster

Edit `automq-cluster.yaml` and replace the S3 bucket placeholders:

```bash
# Replace placeholders with your bucket names
sed -i.bak \
  -e "s|\${OPS_BUCKET}|${OPS_BUCKET}|g" \
  -e "s|\${DATA_BUCKET}|${DATA_BUCKET}|g" \
  -e "s|\${AWS_REGION}|${AWS_REGION}|g" \
  automq-cluster.yaml
```

Or manually edit the file and update these values:
- `${OPS_BUCKET}` → your ops bucket name
- `${DATA_BUCKET}` → your data bucket name  
- `${AWS_REGION}` → your AWS region (e.g., `us-east-1`)

### Step 4: Deploy AutoMQ Cluster

```bash
kubectl apply -f automq-cluster.yaml -n automq
```

### Step 5: Verify Installation

```bash
# Check pod status
kubectl get pods -n automq -w

# Run verification script
./verify.sh
```

All 3 controller pods should be in `Running` state with `1/1` ready.

## Verification

### Check Cluster Status

```bash
# View all pods
kubectl get pods -n automq -o wide

# Check Kafka cluster status
kubectl get kafka -n automq

# View controller logs
kubectl logs my-cluster-controller-0 -n automq --tail=50
```

### Test with Kafka Commands

```bash
# Get controller pod name
CONTROLLER_POD=$(kubectl get pods -n automq -l strimzi.io/pool-name=controller \
  -o jsonpath='{.items[0].metadata.name}')

# Create a test topic
kubectl exec -n automq $CONTROLLER_POD -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --create --topic test-topic --partitions 3 --replication-factor 1

# List topics
kubectl exec -n automq $CONTROLLER_POD -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list

# Produce messages (interactive)
kubectl exec -it -n automq $CONTROLLER_POD -- /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 --topic test-topic

# Consume messages
kubectl exec -it -n automq $CONTROLLER_POD -- /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic test-topic --from-beginning
```

## Configuration

### Default Settings

| Component | Setting | Value |
|-----------|---------|-------|
| Namespace | Name | automq |
| Strimzi | Version | 0.47.0 |
| AutoMQ | Version | 1.6.0-strimzi |
| Kafka | Version | 3.9.0 |
| Controller | Replicas | 3 |
| Controller | Memory Request | 12Gi |
| Controller | Memory Limit | 16Gi |
| Controller | CPU Request | 1000m |
| Controller | CPU Limit | 2000m |
| JVM | Heap | 6GB |
| JVM | Direct Memory | 6GB |
| Storage | Size | 20Gi |

### Node Requirements

AutoMQ requires nodes with sufficient memory. The configuration enforces scheduling only on supported instance types:

- `r6i.large` (16GB RAM) - minimum recommended
- `r6i.xlarge` (32GB RAM)
- `r6i.2xlarge` (64GB RAM)
- `r6in.large` (16GB RAM)
- `r6in.xlarge` (32GB RAM)
- `r6in.2xlarge` (64GB RAM)

### Pod Anti-Affinity

The configuration includes pod anti-affinity rules to ensure each controller/broker runs on a separate node for high availability.

## Cleanup

### Remove AutoMQ Cluster

```bash
# Delete AutoMQ cluster
kubectl delete -f automq-cluster.yaml -n automq

# Wait for pods to terminate
kubectl wait --for=delete pod -l strimzi.io/cluster=my-cluster -n automq --timeout=120s

# Delete PVCs (optional - removes all data)
kubectl delete pvc -l strimzi.io/cluster=my-cluster -n automq
```

### Remove Strimzi Operator

```bash
helm uninstall automq-strimzi-operator -n automq
```

### Remove Namespace

```bash
kubectl delete namespace automq
```

### Remove S3 Buckets (Optional)

```bash
# Empty and delete buckets
aws s3 rb s3://${DATA_BUCKET} --force
aws s3 rb s3://${OPS_BUCKET} --force
```

## Troubleshooting

### Pods Stuck in Pending

Check if nodes meet the instance type requirements:

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,TYPE:.metadata.labels."node\.kubernetes\.io/instance-type"
```

### OOMKilled Errors

Ensure nodes have at least 16GB memory. Check pod resource usage:

```bash
kubectl describe pod my-cluster-controller-0 -n automq | grep -A 10 "Last State"
```

### S3 Access Denied

Verify IAM permissions:

```bash
# Check if pods can access S3
kubectl exec -n automq my-cluster-controller-0 -- \
  aws s3 ls s3://${DATA_BUCKET}/ 2>&1 | head -5
```

### Strimzi Operator Issues

Check operator logs:

```bash
kubectl logs -l name=strimzi-cluster-operator -n automq --tail=100
```

If the operator is stuck, restart it:

```bash
kubectl rollout restart deployment strimzi-cluster-operator -n automq
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     AWS EKS Cluster                              │
│                     (automq namespace)                           │
│                                                                  │
│  ┌──────────────────┐                                            │
│  │ Strimzi Operator │                                            │
│  └────────┬─────────┘                                            │
│           │ manages                                              │
│           ▼                                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ controller-0│  │ controller-1│  │ controller-2│              │
│  │ (KRaft +    │  │ (KRaft +    │  │ (KRaft +    │              │
│  │  Broker)    │  │  Broker)    │  │  Broker)    │              │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘              │
│         │                │                │                      │
│         └────────────────┼────────────────┘                      │
│                          │                                       │
│                    ┌─────┴─────┐                                 │
│                    │  AWS S3   │                                 │
│                    │ (data +   │                                 │
│                    │   ops)    │                                 │
│                    └───────────┘                                 │
└─────────────────────────────────────────────────────────────────┘
```

## References

- [AutoMQ Documentation](https://www.automq.com/docs/automq)
- [Strimzi Documentation](https://strimzi.io/documentation/)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
