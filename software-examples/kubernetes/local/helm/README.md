# AutoMQ Local Deployment with MinIO

This guide provides step-by-step instructions for deploying AutoMQ on a local Kubernetes cluster using MinIO as the object storage backend.

## Prerequisites

- Kubernetes cluster (minikube, kind, Docker Desktop, or similar)
- kubectl CLI configured to access your cluster
- Helm 3.x installed
- Internet access for pulling container images

## Quick Start

### Step 1: Environment Setup

Run the setup script to verify prerequisites and generate the configuration file:

```bash
curl -sSL https://raw.githubusercontent.com/AutoMQ/automq-examples/main/software-examples/kubernetes/local/helm/setup.sh | bash
```

This script will:
- Verify that kubectl and helm are properly installed and configured
- Detect your CPU architecture (amd64/arm64)
- Generate `automq-values.yaml` with appropriate settings

### Step 2: Install MinIO

Deploy MinIO as the object storage backend:

```bash
helm repo add minio https://charts.min.io/

helm install minio minio/minio \
  --set rootUser=admin \
  --set rootPassword=automq_demo_secret \
  --set "buckets[0].name=automq-data,buckets[0].policy=none,buckets[0].purge=false" \
  --set "buckets[1].name=automq-ops,buckets[1].policy=none,buckets[1].purge=false" \
  --set mode=standalone \
  --set service.type=ClusterIP \
  --set persistence.enabled=false \
  --set resources.requests.memory=512Mi \
  --set resources.requests.cpu=250m \
  --set resources.limits.memory=2Gi \
  --set resources.limits.cpu=2 \
  --wait
```

Verify MinIO is running:

```bash
kubectl get pods -l app=minio
```

### Step 3: Install AutoMQ

Deploy AutoMQ using the generated configuration:

```bash
helm install automq oci://automq.azurecr.io/helm/automq-enterprise-chart \
  --version 5.3.4 \
  -f automq-values.yaml \
  --wait
```

Wait for all pods to be ready:

```bash
kubectl get pods -l app.kubernetes.io/instance=automq
```

### Step 4: Verify Installation

Test the cluster by creating a topic:

```bash
./verify.sh
```

Or manually:

```bash
kubectl run kafka-client --rm -it --restart=Never --image=confluentinc/cp-kafka:latest -- \
  kafka-topics --bootstrap-server automq-automq-enterprise-controller-headless:9092 \
  --create --topic test-topic --partitions 3 --replication-factor 1
```

## Cleanup

To remove AutoMQ and MinIO from your cluster:

```bash
./cleanup.sh
```

Or manually:

```bash
# Remove AutoMQ
helm uninstall automq
kubectl delete pvc -l app.kubernetes.io/instance=automq

# Remove MinIO
helm uninstall minio
```

## Configuration

### Default Settings

| Component | Setting | Value |
|-----------|---------|-------|
| MinIO | Root User | admin |
| MinIO | Root Password | automq_demo_secret |
| MinIO | Data Bucket | automq-data |
| MinIO | Ops Bucket | automq-ops |
| AutoMQ | Controller Replicas | 3 |
| AutoMQ | Controller Memory | 2Gi - 4Gi |
| AutoMQ | Controller CPU | 1 - 2 cores |

### Customization

Edit `automq-values.yaml` to customize the deployment. Common adjustments include:
- Controller/Broker replica counts
- Resource limits and requests
- Heap size settings

## Troubleshooting

### Pods not starting

Check pod status and events:

```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### MinIO connection issues

Verify MinIO service is accessible:

```bash
kubectl get svc minio
kubectl run test-minio --rm -it --restart=Never --image=busybox -- \
  wget -qO- http://minio.